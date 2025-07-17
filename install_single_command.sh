#!/bin/bash

# URL base para download dos arquivos do projeto no GitHub
GITHUB_RAW_URL="https://raw.githubusercontent.com/mycroft440/SOCKS5PRO/main/"

# Baixa o script principal de instalação
wget -qO- ${GITHUB_RAW_URL}/install.sh > install.sh || { echo "Erro: Falha ao baixar install.sh"; exit 1; }

# Executa o script principal em modo não interativo (simulando a escolha '1' para instalar o proxy)
echo "1" | sudo bash install.sh

# Limpa o arquivo temporário
rm install.sh


