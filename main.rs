use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use bytes::{BytesMut, Buf};
use std::io::{Error, ErrorKind};
use std::collections::HashMap;
use tokio::fs::File;
use tokio::io::AsyncBufReadExt;
use tokio::io::BufReader;
use log::{info, error};
use std::env;
use tokio::time::{timeout, Duration};
use socket2::{SockRef, TcpKeepalive};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init(); // Inicializa o logger

    let port = env::var("SOCKS5_PORT")
        .unwrap_or_else(|_| "1080".to_string())
        .parse::<u16>()
        .expect("SOCKS5_PORT deve ser um número de porta válido");

    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    info!("Proxy SOCKS5 escutando em 0.0.0.0:{}", port);

    loop {
        let (socket, addr) = listener.accept().await?;
        info!("Nova conexão de: {}", addr);
        tokio::spawn(async move {
            if let Err(e) = handle_client(socket).await {
                error!("Erro ao lidar com o cliente {}: {}", addr, e);
            }
        });
    }
}

async fn load_users() -> Result<HashMap<String, String>, Error> {
    let mut users = HashMap::new();
    let path = "/etc/rusty_socks_proxy/users.txt";
    let file = match File::open(path).await {
        Ok(f) => f,
        Err(e) => {
            if e.kind() == ErrorKind::NotFound {
                info!("Arquivo de usuários não encontrado em {}. Criando um vazio.", path);
                File::create(path).await?;
                return Ok(users);
            } else {
                return Err(e);
            }
        }
    };
    let reader = BufReader::new(file);
    let mut lines = reader.lines();

    while let Some(line) = lines.next_line().await? {
        let parts: Vec<&str> = line.splitn(2, ":").collect();
        if parts.len() == 2 {
            users.insert(parts[0].to_string(), parts[1].to_string());
        }
    }
    Ok(users)
}

async fn peek_stream(stream: &mut TcpStream) -> Result<String, Error> {
    let mut peek_buffer = vec![0; 8192];
    let bytes_peeked = stream.peek(&mut peek_buffer).await?;
    let data = &peek_buffer[..bytes_peeked];
    let data_str = String::from_utf8_lossy(data);
    Ok(data_str.to_string())
}

async fn handle_client(mut socket: TcpStream) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let users = load_users().await?;

    // Get keepalive settings from environment variables
    let keepalive_interval_str = env::var("KEEPALIVE_INTERVAL").unwrap_or_else(|_| "0".to_string());
    let keepalive_count_str = env::var("KEEPALIVE_COUNT_MAX").unwrap_or_else(|_| "0".to_string());

    let keepalive_interval = keepalive_interval_str.parse::<u64>().unwrap_or(0);
    let keepalive_count = keepalive_count_str.parse::<u32>().unwrap_or(0);

    // Apply TCP_NODELAY to client socket
    if let Err(e) = socket.set_nodelay(true) {
        error!("Falha ao configurar TCP_NODELAY para o socket do cliente: {}", e);
    }

    // Apply keepalive to client socket
    if keepalive_interval > 0 {
        let keepalive = TcpKeepalive::new().with_time(Duration::from_secs(keepalive_interval));
        if let Err(e) = SockRef::from(&socket).set_tcp_keepalive(&keepalive) {
            error!("Falha ao configurar keepalive para o socket do cliente: {}", e);
        }
    }

    // SOCKS5 Handshake - Etapa 1: Leitura da saudação do cliente
    let mut buf = BytesMut::with_capacity(256);
    socket.read_buf(&mut buf).await?;

    if buf.len() < 2 {
        return Err(Box::new(Error::new(ErrorKind::InvalidData, "Dados de saudação SOCKS5 insuficientes")));
    }

    let ver = buf.get_u8();
    if ver != 0x05 {
        socket.write_all(&[0x05, 0xFF]).await?;
        return Err(Box::new(Error::new(ErrorKind::InvalidData, "Versão SOCKS não suportada")));
    }

    let nmethods = buf.get_u8();
    if buf.len() < nmethods as usize {
        socket.write_all(&[0x05, 0xFF]).await?;
        return Err(Box::new(Error::new(ErrorKind::InvalidData, "Métodos SOCKS5 incompletos")));
    }

    let mut methods = Vec::with_capacity(nmethods as usize);
    for _ in 0..nmethods {
        methods.push(buf.get_u8());
    }

    // SOCKS5 Handshake - Etapa 2: Seleção do método de autenticação
    let mut auth_success = false;
    if methods.contains(&0x02) { // USERNAME/PASSWORD AUTHENTICATION
        socket.write_all(&[0x05, 0x02]).await?;
        buf.clear();
        socket.read_buf(&mut buf).await?;

        if buf.len() < 2 {
            socket.write_all(&[0x01, 0xFF]).await?;
            return Err(Box::new(Error::new(ErrorKind::InvalidData, "Dados de autenticação insuficientes")));
        }

        let auth_ver = buf.get_u8();
        if auth_ver != 0x01 {
            socket.write_all(&[0x01, 0xFF]).await?;
            return Err(Box::new(Error::new(ErrorKind::InvalidData, "Versão de autenticação não suportada")));
        }

        let ulen = buf.get_u8() as usize;
        if buf.len() < ulen {
            socket.write_all(&[0x01, 0xFF]).await?;
            return Err(Box::new(Error::new(ErrorKind::InvalidData, "Comprimento do nome de usuário inválido")));
        }
        let username = String::from_utf8(buf.split_to(ulen).to_vec())
            .map_err(|_| Error::new(ErrorKind::InvalidData, "Nome de usuário inválido"))?;

        let plen = buf.get_u8() as usize;
        if buf.len() < plen {
            socket.write_all(&[0x01, 0xFF]).await?;
            return Err(Box::new(Error::new(ErrorKind::InvalidData, "Comprimento da senha inválido")));
        }
        let password = String::from_utf8(buf.split_to(plen).to_vec())
            .map_err(|_| Error::new(ErrorKind::InvalidData, "Senha inválida"))?;

        if users.get(&username) == Some(&password) {
            socket.write_all(&[0x01, 0x00]).await?;
            auth_success = true;
            info!("Autenticação SOCKS5 bem-sucedida para o usuário: {}", username);
        } else {
            socket.write_all(&[0x01, 0xFF]).await?;
            error!("Autenticação SOCKS5 falhou para o usuário: {}", username);
            return Err(Box::new(Error::new(ErrorKind::PermissionDenied, "Credenciais inválidas")));
        }
    } else if methods.contains(&0x00) && users.is_empty() { // NO AUTHENTICATION REQUIRED
        socket.write_all(&[0x05, 0x00]).await?;
        auth_success = true;
        info!("Autenticação SOCKS5 sem necessidade de credenciais.");
    } else {
        socket.write_all(&[0x05, 0xFF]).await?;
        return Err(Box::new(Error::new(ErrorKind::PermissionDenied, "Nenhum método de autenticação suportado ou credenciais necessárias.")));
    }

    if !auth_success {
        return Err(Box::new(Error::new(ErrorKind::PermissionDenied, "Falha na autenticação SOCKS5.")));
    }

    // SOCKS5 Handshake - Etapa 3: Leitura da requisição de conexão do cliente
    buf.clear();
    socket.read_buf(&mut buf).await?;

    // VER (1 byte), CMD (1 byte), RSV (1 byte), ATYP (1 byte), DST.ADDR, DST.PORT
    if buf.len() < 4 {
        socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
        return Err(Box::new(Error::new(ErrorKind::InvalidData, "Dados de requisição SOCKS5 insuficientes")));
    }

    let ver = buf.get_u8();
    let cmd = buf.get_u8();
    let rsv = buf.get_u8(); // Reservado, deve ser 0x00
    let atyp = buf.get_u8();

    if ver != 0x05 || rsv != 0x00 {
        // Envia 0x05 (VER), 0x01 (General SOCKS server failure)
        socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
        return Err(Box::new(Error::new(ErrorKind::InvalidData, "Requisição SOCKS5 inválida")));
    }

    if cmd != 0x01 { // Apenas CONNECT (0x01) é suportado
        // Envia 0x05 (VER), 0x07 (Command not supported)
        socket.write_all(&[0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
        return Err(Box::new(Error::new(ErrorKind::Other, "Comando SOCKS5 não suportado")));
    }

    let (mut host, mut port) = match atyp {
        0x01 => { // IPv4
            if buf.len() < 4 {
                socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                return Err(Box::new(Error::new(ErrorKind::InvalidData, "Endereço IPv4 SOCKS5 incompleto")));
            }
            let ip = std::net::Ipv4Addr::new(buf.get_u8(), buf.get_u8(), buf.get_u8(), buf.get_u8());
            let port = buf.get_u16();
            (format!("{}", ip), port)
        }
        0x03 => { // Domain name
            if buf.is_empty() {
                socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                return Err(Box::new(Error::new(ErrorKind::InvalidData, "Comprimento do nome de domínio SOCKS5 ausente")));
            }
            let domain_len = buf.get_u8() as usize;
            if buf.len() < domain_len {
                socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                return Err(Box::new(Error::new(ErrorKind::InvalidData, "Nome de domínio SOCKS5 incompleto")));
            }
            let domain = String::from_utf8(buf.split_to(domain_len).to_vec())
                .map_err(|_| Error::new(ErrorKind::InvalidData, "Nome de domínio SOCKS5 inválido"))?;
            let port = buf.get_u16();
            (domain, port)
        }
        0x04 => { // IPv6
            if buf.len() < 16 {
                socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                return Err(Box::new(Error::new(ErrorKind::InvalidData, "Endereço IPv6 SOCKS5 incompleto")));
            }
            let mut ip_bytes = [0u8; 16];
            buf.copy_to_slice(&mut ip_bytes);
            let ip = std::net::Ipv6Addr::from(ip_bytes);
            let port = buf.get_u16();
            (format!("{}", ip), port)
        }
        _ => {
            // Envia 0x05 (VER), 0x08 (Address type not supported)
            socket.write_all(&[0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            return Err(Box::new(Error::new(ErrorKind::InvalidData, "Tipo de endereço SOCKS5 não suportado")));
        }
    };

    // Inspecionar o tráfego para determinar se é SSH
    let initial_data = timeout(Duration::from_secs(1), peek_stream(&mut socket)).await
        .unwrap_or_else(|_| Ok(String::new()));

    let mut target_host = host.clone();
    let mut target_port = port;

    if let Ok(data) = initial_data {
        if data.contains("SSH") {
            info!("Tráfego SSH detectado. Encaminhando para localhost:22");
            target_host = "127.0.0.1".to_string();
            target_port = 22;
        } else {
            info!("Tráfego não-SSH. Encaminhando para {}:{}", host, port);
        }
    } else {
        info!("Não foi possível inspecionar o tráfego inicial. Encaminhando para {}:{}", host, port);
    }

    info!("Conectando a: {}:{}", target_host, target_port);

    // Conexão direta ao destino
    let mut destination = match TcpStream::connect(format!("{}:{}", target_host, target_port)).await {
        Ok(s) => s,
        Err(e) => {
            error!("Falha ao conectar ao destino {}:{}: {}", target_host, target_port, e);
            socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            return Err(Box::new(e));
        }
    };

    // Apply TCP_NODELAY to destination socket
    if let Err(e) = destination.set_nodelay(true) {
        error!("Falha ao configurar TCP_NODELAY para o socket de destino: {}", e);
    }

    // Apply keepalive to destination socket
    if keepalive_interval > 0 {
        let keepalive = TcpKeepalive::new().with_time(Duration::from_secs(keepalive_interval));
        if let Err(e) = SockRef::from(&destination).set_tcp_keepalive(&keepalive) {
            error!("Falha ao configurar keepalive para o socket de destino: {}", e);
        }
    }

    // SOCKS5 Handshake - Etapa 4: Resposta de sucesso ao cliente
    // Resposta de sucesso: 0x05 (VER), 0x00 (SUCCES), 0x00 (RSV), ATYP, BND.ADDR, BND.PORT
    // Usamos 0.0.0.0:0 como endereço e porta de ligação, pois não é relevante para o cliente SOCKS
    socket.write_all(&[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;

    // Transferência de dados bidirecional
    let (mut client_read, mut client_write) = tokio::io::split(socket);
    let (mut destination_read, mut destination_write) = tokio::io::split(destination);

    tokio::try_join!(
        tokio::io::copy(&mut client_read, &mut destination_write),
        tokio::io::copy(&mut destination_read, &mut client_write)
    )?;

    Ok(())
}
