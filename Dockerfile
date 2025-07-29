# ---- Estágio 1: Builder ----
# Usamos uma imagem base Alpine Linux
FROM alpine:3.18 as builder

# Define variáveis de ambiente para o PHP (mantido para boa prática, mas chamaremos php82 explicitamente)
ENV PATH="/usr/bin:${PATH}"

# Instala dependências do sistema, incluindo PHP 8.2 e suas extensões necessárias
RUN apk add --no-cache \
    php82 \
    php82-fpm \
    php82-pdo \
    php82-pdo_mysql \
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
    php82-session \
    composer \
    nodejs \
    npm \
    git \
    # Adicionando dependências de desenvolvimento que podem ser necessárias para extensões
    libxml2-dev \
    libzip-dev \
    libpng-dev \
    jpeg-dev \
    freetype-dev \
    icu-dev

# Verifica a versão do PHP para depuração (saída no log de build)
RUN php82 -v

# Define o diretório de trabalho
WORKDIR /var/www

# Copia o restante dos arquivos da aplicação, incluindo composer.json e composer.lock
# O .dockerignore garantirá que 'vendor' e 'node_modules' não sejam copiados neste momento,
# pois serão gerados no container.
COPY . .

# Limpa o cache do Composer e instala as dependências.
# Este passo agora ocorre DEPOIS que todo o código da aplicação foi copiado.
# Chamando 'composer' com 'php82' explicitamente para garantir a versão correta
RUN php82 /usr/bin/composer clear-cache && \
    php82 /usr/bin/composer install --no-interaction --optimize-autoloader --no-dev

# Instala dependências do front-end e compila os assets
# Este passo também ocorre DEPOIS que todo o código da aplicação foi copiado.
RUN npm install && npm run build

# Otimiza o Laravel para produção
# Chamando 'artisan' com 'php82' explicitamente
RUN php82 artisan optimize:clear
RUN php82 artisan config:cache
RUN php82 artisan route:cache
RUN php82 artisan view:cache

# ---- Estágio 2: Produção ----
# Usamos uma imagem limpa e leve para a aplicação final
FROM alpine:3.18

# Instala apenas as dependências necessárias para rodar a aplicação em produção
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
    php82-session \
    nginx \
    supervisor

# Garante que o comando 'php' aponte para php82 também no estágio de produção
# Este symlink é mantido aqui para garantir que qualquer chamada genérica 'php' no ambiente de execução use php82
RUN ln -sf /usr/bin/php82 /usr/bin/php

# Define o diretório de trabalho
WORKDIR /var/www

# Copia os arquivos construídos do estágio anterior
# Isso inclui o diretório 'vendor' que foi gerado no estágio 'builder'
COPY --from=builder /var/www .

# Copia os arquivos de configuração do Nginx e Supervisor
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisord.conf /etc/supervisord.conf

# Ajusta permissões das pastas para o usuário www-data
RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache && \
    chmod -R 775 /var/www/storage /var/www/bootstrap/cache

# Expõe a porta que o Cloud Run usará
EXPOSE 8080

# Comando para iniciar o Supervisor, que gerencia Nginx e PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
