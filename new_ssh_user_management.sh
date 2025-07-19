#!/bin/bash

# Arquivo de usuários para o proxy SOCKS5
SOCKS5_USERS_FILE="/etc/rusty_socks_proxy/users.txt"

# Garante que o diretório e o arquivo de usuários existam
sudo mkdir -p /etc/rusty_socks_proxy/
sudo touch $SOCKS5_USERS_FILE

# Função para criar um usuário SSH e SOCKS5
create_ssh_user() {
    echo "\n--- Criar Usuário SSH e SOCKS5 ---"
    read -p "Digite o nome de usuário: " USERNAME
    read -s -p "Digite a senha para o usuário $USERNAME: " PASSWORD
    echo

    if id "$USERNAME" &>/dev/null; then
        echo "[ERRO] Usuário $USERNAME já existe no sistema."
        return 1
    fi

    # Criar usuário do sistema
    sudo useradd -m -s /bin/bash "$USERNAME" || { echo "[ERRO] Erro ao criar usuário do sistema."; return 1; }
    echo "$USERNAME:$PASSWORD" | sudo chpasswd || { echo "[ERRO] Erro ao definir senha do usuário do sistema."; return 1; }
    echo "[INFO] Usuário do sistema $USERNAME criado com sucesso."

    # Adicionar usuário ao arquivo do SOCKS5
    echo "$USERNAME:$PASSWORD" | sudo tee -a $SOCKS5_USERS_FILE > /dev/null || { echo "[ERRO] Erro ao adicionar usuário SOCKS5."; return 1; }
    echo "[INFO] Usuário SOCKS5 $USERNAME adicionado com sucesso."
    echo "[SUCESSO] Usuário $USERNAME criado para SSH e SOCKS5."
}

# Função para remover um usuário SSH e SOCKS5
remove_ssh_user() {
    echo "\n--- Remover Usuário SSH e SOCKS5 ---"
    read -p "Digite o nome de usuário a ser removido: " USERNAME

    if ! id "$USERNAME" &>/dev/null; then
        echo "[ERRO] Usuário $USERNAME não existe no sistema."
        return 1
    fi

    # Remover usuário do sistema
    sudo userdel -r "$USERNAME" || { echo "[ERRO] Erro ao remover usuário do sistema."; return 1; }
    echo "[INFO] Usuário do sistema $USERNAME removido com sucesso."

    # Remover usuário do arquivo do SOCKS5
    sudo sed -i "/^$USERNAME:/d" $SOCKS5_USERS_FILE || { echo "[ERRO] Erro ao remover usuário SOCKS5."; return 1; }
    echo "[INFO] Usuário SOCKS5 $USERNAME removido com sucesso."
    echo "[SUCESSO] Usuário $USERNAME removido de SSH e SOCKS5."
}

# Função para listar usuários SSH e SOCKS5
list_ssh_users() {
    echo "\n--- Listar Usuários SSH e SOCKS5 ---"
    echo "[INFO] Usuários do Sistema (SSH):"
    getent passwd | grep -E ":/home/" | cut -d: -f1

    echo "\n[INFO] Usuários SOCKS5 (do arquivo $SOCKS5_USERS_FILE):"
    if [ -f "$SOCKS5_USERS_FILE" ]; then
        cut -d: -f1 $SOCKS5_USERS_FILE
    else
        echo "[AVISO] Arquivo de usuários SOCKS5 não encontrado."
    fi
}


