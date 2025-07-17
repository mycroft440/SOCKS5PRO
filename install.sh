#!/bin/bash

# Função para exibir mensagens de erro e sair
error_exit() {
    echo "Erro: $1" >&2
    exit 1
}

# Diretório de destino para o projeto
PROJECT_DIR="/opt/rusty_socks_proxy"

# URL base para download dos arquivos do projeto no GitHub
GITHUB_RAW_URL="https://raw.githubusercontent.com/mycroft440/SOCKS5PRO/main/"

# Função para instalar o proxy
install_proxy_single_command( ) {
    clear
    echo "\n--- Instalar Rusty SOCKS5 Proxy ---"
    echo "[INFO] Iniciando a instalação do Rusty SOCKS5 Proxy...\n"

    # 1. Instalar Rust e Cargo
    echo "[INFO] Verificando e instalando Rust e Cargo...\n"
    if ! command -v cargo &>/dev/null; then
        curl --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || error_exit "[ERRO] Falha ao instalar Rust.\n"
    # O rustup já configura o PATH, mas para garantir que esteja disponível imediatamente
    export PATH="/root/.cargo/bin:$PATH"
    source $HOME/.cargo/env || source /root/.cargo/env || echo "[AVISO] Não foi possível carregar o ambiente do Cargo. Verifique manualmente." 
        echo "[SUCESSO] Rust e Cargo instalados.\n"
    else
        echo "[INFO] Rust e Cargo já estão instalados.\n"
    fi

    # 2. Instalar build-essential
    echo "[INFO] Atualizando pacotes e instalando build-essential...\n"
    sudo apt update >&/dev/null || error_exit "[ERRO] Falha ao atualizar pacotes.\n"
    sudo apt install build-essential -y &>/dev/null || error_exit "[ERRO] Falha ao instalar build-essential.\n"
    echo "[SUCESSO] build-essential instalado.\n"

    # 3. Mover arquivos do projeto para um diretório padrão
    echo "[INFO] Criando diretório do projeto em $PROJECT_DIR...\n"
    sudo mkdir -p $PROJECT_DIR || error_exit "[ERRO] Falha ao criar diretório do projeto.\n"

    echo "[INFO] Baixando arquivos do projeto para $PROJECT_DIR...\n"
    sudo mkdir -p $PROJECT_DIR/src || error_exit "[ERRO] Falha ao criar diretório src.\n"

    # Baixar arquivos necessários para a compilação do GitHub
    sudo wget -qO $PROJECT_DIR/src/Cargo.toml ${GITHUB_RAW_URL}/Cargo.toml || error_exit "[ERRO] Falha ao baixar Cargo.toml.\n"
    sudo wget -qO $PROJECT_DIR/src/main.rs ${GITHUB_RAW_URL}/main.rs || error_exit "[ERRO] Falha ao baixar main.rs.\n"
    sudo wget -qO $PROJECT_DIR/rusty_socks_proxy.service ${GITHUB_RAW_URL}/rusty_socks_proxy.service || error_exit "[ERRO] Falha ao baixar rusty_socks_proxy.service.\n"
    echo "[SUCESSO] Arquivos do projeto baixados do GitHub.\n"

    # 4. Compilar o projeto Rust
    echo "[INFO] Compilando o projeto Rust...\n"
    # Navega para o diretório onde o Cargo.toml está para compilar
    source /root/.cargo/env || error_exit "[ERRO] Falha ao carregar o ambiente do Cargo."
    (cd $PROJECT_DIR/src && sudo -E /root/.cargo/bin/cargo build --release ) &>/dev/null || error_exit "[ERRO] Falha ao compilar o projeto Rust.\n"
    echo "[SUCESSO] Projeto Rust compilado.\n"

    # 5. Mover o executável compilado
    echo "[INFO] Movendo o executável compilado...\n"
    sudo mv $PROJECT_DIR/src/target/release/rusty_socks_proxy $PROJECT_DIR/rusty_socks_proxy || error_exit "[ERRO] Falha ao mover o executável.\n"
    echo "[SUCESSO] Executável movido.\n"

    # 6. Configurar e iniciar o serviço systemd
    echo "[INFO] Configurando e iniciando o serviço systemd...\n"
    sudo cp $PROJECT_DIR/rusty_socks_proxy.service /etc/systemd/system/rusty_socks_proxy.service || error_exit "[ERRO] Falha ao copiar o arquivo de serviço.\n"
    sudo systemctl daemon-reload || error_exit "[ERRO] Falha ao recarregar o daemon do systemd.\n"
    sudo systemctl enable rusty_socks_proxy || error_exit "[ERRO] Falha ao habilitar o serviço.\n"
    sudo systemctl start rusty_socks_proxy || error_exit "[ERRO] Falha ao iniciar o serviço.\n"
    echo "[SUCESSO] Serviço Rusty SOCKS5 Proxy configurado e iniciado.\n"

    echo "\n--- Instalação Concluída ---"
    echo "O Rusty SOCKS5 Proxy foi instalado e está rodando como um serviço systemd.\n"
    echo "Você pode verificar o status com: sudo systemctl status rusty_socks_proxy\n"
    echo "\nPara gerenciar usuários SSH, execute: sudo bash /home/ubuntu/project/new_ssh_user_management.sh\n"
}

# Função para gerenciar usuários SSH
manage_ssh_users_menu() {
    # Inclui o script de gerenciamento de usuários SSH
    # ATENÇÃO: Este caminho deve ser ajustado se o script new_ssh_user_management.sh não estiver no mesmo diretório ou não for baixado.
    source /home/ubuntu/project/new_ssh_user_management.sh || error_exit "[ERRO] Falha ao carregar new_ssh_user_management.sh. Verifique o caminho."

    while true; do
        clear
        echo "\n--- Gerenciamento de Usuários SSH ---"
        echo "1. Criar Usuário SSH"
        echo "2. Remover Usuário SSH"
        echo "3. Listar Usuários SSH"
        echo "4. Voltar ao Menu Principal"
        echo "------------------------------------"
        read -p "Escolha uma opção: " choice

        case $choice in
            1) create_ssh_user ;;
            2) remove_ssh_user ;;
            3) list_ssh_users ;;
            4) break ;;
            *) echo "Opção inválida. Tente novamente." ;;
        esac
        read -p "Pressione Enter para continuar..." # Pausa para o usuário ler a saída
    done
}

# Menu principal
main_menu() {
    while true; do
        clear
        echo "\n--- Menu Principal do Instalador Rusty SOCKS5 Proxy ---"
        echo "1. Instalar Rusty SOCKS5 Proxy"
        echo "2. Gerenciar Usuários SSH"
        echo "3. Sair"
        echo "----------------------------------------------------"
        read -p "Escolha uma opção: " choice

        case $choice in
            1) install_proxy_single_command ;;
            2) manage_ssh_users_menu ;;
            3) echo "Saindo..." ; exit 0 ;;
            *) echo "Opção inválida. Tente novamente." ;;
        esac
        read -p "Pressione Enter para continuar..." # Pausa para o usuário ler a saída
    done
}

# Inicia o menu principal
main_menu
