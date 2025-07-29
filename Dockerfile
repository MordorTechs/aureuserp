# Usa a imagem base do PHP com FPM para a versão 8.2
FROM php:8.2-fpm

# Define o diretório de trabalho dentro do contêiner
WORKDIR /var/www/html

# Instala as dependências do sistema e extensões PHP necessárias
# Inclui git, unzip, libpq-dev (para PostgreSQL), libpng-dev, libjpeg-dev, libzip-dev
# e outras extensões PHP comuns para aplicações Laravel.
# Adicionadas as bibliotecas libicu-dev para resolver o erro 'icu-uc icu-io icu-i18n not found'.
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libpq-dev \
    libpng-dev \
    libjpeg-dev \
    libzip-dev \
    supervisor \
    nginx \
    curl \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# Instala as extensões PHP
# Adicionada a extensão 'intl' e 'pdo_mysql' para resolver os erros.
RUN docker-php-ext-install pdo pdo_pgsql zip gd intl pdo_mysql

# Instala o Composer
# Baixa o instalador do Composer, verifica sua integridade e move para /usr/local/bin
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Copia os arquivos da aplicação para o diretório de trabalho
# O .dockerignore deve ser configurado para excluir o diretório vendor e node_modules
COPY . .

# Cria um arquivo .env temporário com a conexão MySQL para o processo de build
# Isso evita que o Laravel tente usar o SQLite durante a fase de build.
RUN echo "APP_ENV=production" > .env \
    && echo "APP_KEY=base64:YOUR_APP_KEY_HERE" >> .env \
    && echo "DB_CONNECTION=mysql" >> .env \
    && echo "DB_HOST=localhost" >> .env \
    && echo "DB_PORT=3306" >> .env \
    && echo "DB_DATABASE=temp_db" >> .env \
    && echo "DB_USERNAME=temp_user" >> .env \
    && echo "DB_PASSWORD=temp_password" >> .env

# Define as permissões para o diretório de armazenamento e cache
# Isso é crucial para que o Laravel possa gravar arquivos de log, cache, sessões, etc.
RUN chown -R www-data:www-data /var/www/html/storage \
    && chown -R www-data:www-data /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache

# Limpa o cache do Composer e reinstala as dependências
# Isso ajuda a resolver problemas de instalação de pacotes corrompidos ou inconsistentes.
# --no-interaction: Não faz perguntas durante a instalação.
# --optimize-autoloader: Otimiza o autoloader para melhor desempenho em produção.
# --no-dev: Não instala pacotes de desenvolvimento.
RUN composer clear-cache \
    && rm -rf vendor/ \
    && rm composer.lock || true \
    && composer install --no-interaction --optimize-autoloader --no-dev

# Executa as migrações do banco de dados Laravel
# O flag --force é necessário para executar em ambiente de produção sem confirmação interativa.
RUN php artisan migrate --force

# Remove o arquivo .env temporário após o build
# O arquivo .env real será injetado pelo Cloud Run como variáveis de ambiente em tempo de execução.
RUN rm .env

# Copia a configuração do Nginx
# Assume que você tem um arquivo nginx.conf no diretório docker/nginx.conf
COPY docker/nginx.conf /etc/nginx/sites-available/default

# Remove a configuração padrão do Nginx e cria um link simbólico para a nova configuração
RUN rm /etc/nginx/sites-enabled/default \
    && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Copia a configuração do Supervisor
# Assume que você tem um arquivo supervisord.conf no diretório docker/supervisord.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expõe a porta 8080 para acesso via HTTP, conforme exigido pelo Google Cloud Run
EXPOSE 8080

# Inicia o Supervisor, que por sua vez iniciará o Nginx e o PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
