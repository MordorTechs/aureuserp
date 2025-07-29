# ---- Estágio 1: Builder ----
# Usamos uma imagem com PHP e Node.js para construir a aplicação
FROM alpine:3.18 as builder

# Instala dependências do sistema
RUN apk add --no-cache \
    php82 \
    php82-fpm \
    php82-pdo \
    php82-pdo_mysql \
    php82-pdo_sqlite \
    php82-tokenizer \
    php82-xml \
    php82-dom \
    php82-xmlwriter \
    php82-ctype \
    php82-mbstring \
    php82-openssl \
    php82-gd \
    php82-curl \
    php82-zip \
    php82-intl \
    php82-bcmath \
    php82-fileinfo \
    php82-exif \
    php82-pcntl \
    php82-sockets \
    php82-session \
    composer \
    nodejs \
    npm \
    git

# Garante que o comando 'php' aponte para a versão 8.2 em todo o estágio de build
RUN ln -sf /usr/bin/php82 /usr/bin/php

# Define o diretório de trabalho
WORKDIR /var/www

# Copia todos os arquivos da aplicação
COPY . .

# --- CORREÇÃO IMPORTANTE ---
# Executa todos os passos de build em uma única camada com a ordem correta e chamando 'php82' explicitamente.
RUN set -e && \
    echo "Creating temporary .env file and database for build..." && \
    touch database/database.sqlite && \
    echo "APP_KEY=" > .env && \
    echo "DB_CONNECTION=sqlite" >> .env && \
    echo "DB_DATABASE=/var/www/database/database.sqlite" >> .env && \
    echo "CACHE_DRIVER=array" >> .env && \
    echo "SESSION_DRIVER=array" >> .env && \
    \
    echo "Installing Composer dependencies with PHP 8.2..." && \
    php82 /usr/bin/composer install --no-interaction --optimize-autoloader --no-dev --ignore-platform-reqs && \
    \
    echo "Generating application key with PHP 8.2..." && \
    php82 artisan key:generate --force && \
    \
    echo "Building frontend assets..." && \
    npm install && npm run build && \
    \
    echo "Running migrations on temporary database with PHP 8.2..." && \
    php82 artisan migrate --force && \
    \
    echo "Optimizing Laravel application with PHP 8.2..." && \
    php82 artisan config:cache && \
    php82 artisan route:cache && \
    php82 artisan view:cache && \
    \
    echo "Cleaning up temporary build files..." && \
    rm .env database/database.sqlite

# ---- Estágio 2: Produção ----
# Usamos uma imagem limpa e leve para a aplicação final
FROM alpine:3.18

# Instala apenas as dependências necessárias para rodar
RUN apk add --no-cache \
    php82 \
    php82-fpm \
    php82-pdo \
    php82-pdo_mysql \
    php82-tokenizer \
    php82-xml \
    php82-ctype \
    php82-mbstring \
    php82-openssl \
    php82-gd \
    php82-curl \
    php82-zip \
    php82-intl \
    php82-bcmath \
    php82-fileinfo \
    php82-exif \
    php82-pcntl \
    php82-sockets \
    php82-session \
    nginx \
    supervisor

# Garante que o comando 'php' aponte para a versão 8.2 na imagem final
RUN ln -sf /usr/bin/php82 /usr/bin/php

# Define o diretório de trabalho
WORKDIR /var/www

# Copia os arquivos construídos do estágio anterior
COPY --from=builder /var/www .

# Copia os arquivos de configuração do Nginx e Supervisor
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisord.conf /etc/supervisord.conf

# Ajusta permissões das pastas
RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache && \
    chmod -R 775 /var/www/storage /var/www/bootstrap/cache

# Expõe a porta que o Cloud Run usará
EXPOSE 8080

# Comando para iniciar o Supervisor, que gerencia Nginx e PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
