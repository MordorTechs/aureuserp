# ---- Estágio 1: Builder ----
# Usamos uma imagem com PHP e Node.js para construir a aplicação
FROM alpine:3.18 as builder

# Instala dependências do sistema, incluindo extensões extras para maior compatibilidade
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

# Garante que o comando 'php' aponte para a versão 8.2
RUN ln -sf /usr/bin/php82 /usr/bin/php

# Define o diretório de trabalho
WORKDIR /var/www

# Copia todos os arquivos da aplicação ANTES de instalar as dependências.
COPY . .

# --- CORREÇÃO IMPORTANTE ---
# Configura um banco de dados SQLite em memória APENAS para o processo de build.
# Isso evita a necessidade de um arquivo físico ou uma conexão real com o MySQL durante a compilação.
ENV DB_CONNECTION=sqlite
ENV DB_DATABASE=:memory:

# Instala as dependências do Composer
RUN composer install --no-interaction --optimize-autoloader --no-dev --ignore-platform-reqs

# Instala dependências do front-end e compila os assets
RUN npm install && npm run build

# Otimiza o Laravel para produção
RUN php artisan optimize:clear
RUN php artisan config:cache
RUN php artisan route:cache
RUN php artisan view:cache

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
