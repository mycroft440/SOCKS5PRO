#!/bin/bash

# Função para exibir mensagens de erro e sair
error_exit() {
    echo "Erro: $1" >&2
    exit 1
}

# Diretório de destino para o projeto
PROJECT_DIR="/opt/rusty_socks_proxy"

# Caminho para o script de gerenciamento de usuários SSH
SSH_USER_MANAGEMENT_SCRIPT="/opt/rusty_socks_proxy/new_ssh_user_management.sh"

# URL base para download dos arquivos do projeto no GitHub
GITHUB_RAW_URL="https://raw.githubusercontent.com/mycroft440/SOCKS5PRO/main/"

# Instalar Rust e Cargo para o root, se não estiverem instalados
    if ! sudo -i bash -c "command -v cargo &>/dev/null"; then
        echo "[INFO] Instalando Rust e Cargo para o root...\n"
        curl --tlsv1.2 -sSf https://sh.rustup.rs | sudo sh -s -- -y --no-modify-path || error_exit "[ERRO] Falha ao instalar Rust para root.\n"
        sudo -i bash -c "/root/.cargo/bin/rustup default stable" || echo "[AVISO] Não foi possível configurar o rustup default stable para o root."
        echo "[SUCESSO] Rust e Cargo instalados para o root.\n"
    else
        echo "[INFO] Rust e Cargo já estão instalados para o root.\n"
    fi

# Função para instalar o proxy
install_proxy_single_command() {
    clear
    echo "\n--- Instalar Rusty SOCKS5 Proxy ---"
    read -p "Digite a porta para o Rusty SOCKS5 Proxy (padrão: 1080): " SOCKS5_PORT
    SOCKS5_PORT=${SOCKS5_PORT:-1080}
    export SOCKS5_PORT

    echo "[INFO] Iniciando a instalação do Rusty SOCKS5 Proxy na porta $SOCKS5_PORT...\n"



    # 2. Instalar build-essential
    echo "[INFO] Atualizando pacotes e instalando build-essential...\n"
    sudo apt update >&/dev/null || error_exit "[ERRO] Falha ao atualizar pacotes.\n"
    sudo apt install build-essential -y || error_exit "[ERRO] Falha ao instalar build-essential.\n"
    echo "[SUCESSO] build-essential instalado.\n"

    # 3. Mover arquivos do projeto para um diretório padrão
    echo "[INFO] Criando diretório do projeto em $PROJECT_DIR...\n"
    sudo mkdir -p $PROJECT_DIR || error_exit "[ERRO] Falha ao criar diretório do projeto.\n"

    echo "[INFO] Baixando arquivos do projeto para $PROJECT_DIR...\n"
    sudo mkdir -p $PROJECT_DIR/src || error_exit "[ERRO] Falha ao criar diretório src.\n"


    sudo wget -qO "$PROJECT_DIR/new_ssh_user_management.sh" "${GITHUB_RAW_URL}/new_ssh_user_management.sh" || error_exit "[ERRO] Falha ao baixar new_ssh_user_management.sh.\n"

    # 4. Compilar o projeto Rust
    echo "[INFO] Compilando o projeto Rust...\n"
    # Navega para o diretório onde o Cargo.toml está para compilar

    sudo -i bash -c "cd $PROJECT_DIR/src && export PATH=\"/root/.cargo/bin:\$PATH\" && /root/.cargo/bin/cargo build --release" || error_exit "[ERRO] Falha ao compilar o projeto Rust.\n"
    echo "[SUCESSO] Projeto Rust compilado.\n"

    # 5. Mover o executável compilado
    echo "[INFO] Movendo o executável compilado...\n"
    sudo mv $PROJECT_DIR/src/target/release/rusty_socks_proxy $PROJECT_DIR/rusty_socks_proxy || error_exit "[ERRO] Falha ao mover o executável.\n"
    echo "[SUCESSO] Executável movido.\n"

    # 6. Configurar e iniciar o serviço systemd
    echo "[INFO] Configurando e iniciando o serviço systemd...\n"
    sudo cp $PROJECT_DIR/rusty_socks_proxy.service /etc/systemd/system/rusty_socks_proxy.service || error_exit "[ERRO] Falha ao copiar o arquivo de serviço.\n"
    sudo sed -i "s|ExecStart=.*|ExecStart=$PROJECT_DIR/rusty_socks_proxy|g" /etc/systemd/system/rusty_socks_proxy.service || error_exit "[ERRO] Falha ao configurar o caminho do executável no arquivo de serviço.\n"
    sudo sed -i "s|Environment=\"SOCKS5_PORT=.*|Environment=\"SOCKS5_PORT=$SOCKS5_PORT\"|g" /etc/systemd/system/rusty_socks_proxy.service || error_exit "[ERRO] Falha ao configurar a porta no arquivo de serviço.\n"
    sudo systemctl daemon-reload || error_exit "[ERRO] Falha ao recarregar o daemon do systemd.\n"
    sudo systemctl enable rusty_socks_proxy || error_exit "[ERRO] Falha ao habilitar o serviço.\n"
    sudo systemctl start rusty_socks_proxy || error_exit "[ERRO] Falha ao iniciar o serviço.\n"
    echo "[SUCESSO] Serviço Rusty SOCKS5 Proxy configurado e iniciado na porta $SOCKS5_PORT.\n"
    echo "Você pode verificar o status com: sudo systemctl status rusty_socks_proxy\n"
    echo "\nPara gerenciar usuários SSH, execute: sudo bash $SSH_USER_MANAGEMENT_SCRIPT\n"
} || error_exit "[ERRO] Falha na instalação completa do Rusty SOCKS5 Proxy.\n"

# Função para gerenciar usuários SSH
manage_ssh_users_menu() {
    # Inclui o script de gerenciamento de usuários SSH
    if [ -f "$SSH_USER_MANAGEMENT_SCRIPT" ]; then
        source "$SSH_USER_MANAGEMENT_SCRIPT" &>/dev/null # Redireciona stdout e stderr para /dev/null
    else
        echo "[ERRO] Script de gerenciamento de usuários SSH não encontrado: $SSH_USER_MANAGEMENT_SCRIPT"
        read -p "Pressione Enter para continuar..."
        return 1
    fi

    while true; do
        clear
        echo "\n--- Gerenciamento de Usuários SSH ---"
        echo "1. Criar Usuário SSH"
        echo "2. Remover Usuário SSH"
        echo "3. Listar Usuários SSH"
        echo "4. Voltar ao Menu Principal"
        echo "------------------------------------"
        read -p "Escolha uma opção: " choice

        # Validação de entrada: verifica se a escolha é um número e está dentro das opções válidas
        if ! [[ "$choice" =~ ^[1-4]$ ]]; then
            echo "Opção inválida. Tente novamente."
            read -p "Pressione Enter para continuar..."
            continue
        fi

        case $choice in
            1) create_ssh_user ;;
            2) remove_ssh_user ;;
            3) list_ssh_users ;;
            4) break ;;
        esac
        # Adiciona uma pausa apenas se a opção não for sair
        if [[ "$choice" != "4" ]]; then
            read -p "Pressione Enter para continuar..."
        fi
    done
}


# Função para exibir o status do serviço e a porta
show_status() {
    clear
    echo "\n--- Status do Rusty SOCKS5 Proxy ---"
    SERVICE_STATUS=$(sudo systemctl is-active rusty_socks_proxy)
    SERVICE_ENABLED=$(sudo systemctl is-enabled rusty_socks_proxy)

    echo "Status do Serviço: $SERVICE_STATUS"
    echo "Habilitado na Inicialização: $SERVICE_ENABLED"

    # Tenta obter a porta do arquivo de serviço ou da variável de ambiente
    PORT=$(grep -oP "(?<=Environment=\"SOCKS5_PORT=)[0-9]+" /etc/systemd/system/rusty_socks_proxy.service 2>/dev/null || echo $SOCKS5_PORT)
    if [ -z "$PORT" ]; then
        PORT="Não Definida (Padrão: 1080)"
    fi
    echo "Porta do SOCKS5: $PORT"

    echo "------------------------------------"
    read -p "Pressione Enter para continuar..."
}

# Menu principal
main_menu() {
    while true; do
        clear
        echo "

        ███╗   ███╗██╗   ██╗███╗   ██╗███████╗██╗     ██████╗ ██╗    ██╗ ██████╗ 
        ████╗ ████║██║   ██║████╗  ██║██╔════╝██║     ██╔══██╗██║    ██║██╔═══██╗
        ██╔████╔██║██║   ██║██╔██╗ ██║█████╗  ██║     ██████╔╝██║ █╗ ██║██║   ██║
        ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══╝  ██║     ██╔══██╗██║███╗██║██║   ██║
        ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████╗███████╗██║  ██║╚███╔███╔╝╚██████╔╝
        ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═══╝╚═══╝ ╚═════╝ 
                                                                               
        --- Bem-vindo ao multiflow manager ---"

        echo "1. 🚀 Instalar Rusty SOCKS5 Proxy"
        echo "2. 👥 Gerenciar Usuários SSH"
        echo "3. 📊 Status do Serviço"
        echo "4. 🚪 Sair"
        echo "----------------------------------------------------"
        read -p "Escolha uma opção: " choice

        # Validação de entrada: verifica se a escolha é um número e está dentro das opções válidas
        if ! [[ "$choice" =~ ^[1-4]$ ]]; then
            echo "Opção inválida. Tente novamente."
            read -p "Pressione Enter para continuar..."
            continue
        fi

        case $choice in
            1) install_proxy_single_command ;;
            2) 
                if [ -f "$SSH_USER_MANAGEMENT_SCRIPT" ]; then
                    manage_ssh_users_menu
                else
                    echo "[AVISO] A funcionalidade de gerenciamento de usuários SSH não está disponível. O script de gerenciamento de usuários SSH não foi encontrado ou não pôde ser carregado."
                    read -p "Pressione Enter para continuar..."
                fi
                ;;
            3) show_status ;;
            4) echo "Saindo..." ; exit 0 ;;
        esac
    done
}

# Inicia o menu principal
main_menu

