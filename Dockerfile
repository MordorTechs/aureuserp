#
# Dockerfile para Aplicação Laravel (Krayin CRM) - Otimizado para Cloud Run
#

# --- ESTÁGIO 1: Base ---
# Usamos uma imagem base com PHP 8.2 e FPM.
FROM php:8.2-fpm as base

# Define o diretório de trabalho
WORKDIR /var/www

# Instala dependências do sistema, Nginx, Supervisor e extensões PHP.
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    zip \
    nginx \
    supervisor \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd pdo pdo_mysql mbstring exif pcntl bcmath zip intl calendar sockets

# Instala o Composer globalmente
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copia o arquivo .env.example para .env.
COPY .env.example .env

# --- ESTÁGIO 2: Builder ---
# Este estágio é responsável por instalar todas as dependências (PHP e JS) e compilar os assets.
FROM base as builder

# Instala Node.js e NPM.
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Copia os arquivos de definição de dependências.
COPY composer.json composer.lock ./
COPY package.json ./

# Copia todos os arquivos da aplicação ANTES de rodar o composer install.
COPY . .

# Instala as dependências do PHP.
RUN composer install --no-interaction --optimize-autoloader --no-dev

# Instala as dependências do Node e compila os assets.
RUN npm install
RUN npm run build

# Limpa o cache.
RUN php artisan optimize:clear

# --- ESTÁGIO 3: Produção ---
# Este é o estágio final que irá gerar a imagem limpa e otimizada para o Cloud Run.
FROM base as production

# Copia o código da aplicação e as dependências do estágio 'builder'.
COPY --from=builder /var/www .

# Copia os arquivos de configuração do Nginx e do Supervisor.
COPY nginx.conf /etc/nginx/sites-available/default
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copia o script de inicialização e o torna executável.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Define o usuário 'www-data' como dono dos diretórios e ajusta as permissões.
RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache \
    && chmod -R 775 /var/www/storage /var/www/bootstrap/cache

# Expõe a porta 8080, que é a porta padrão que o Cloud Run espera.
EXPOSE 8080

# Define o script de inicialização como o ponto de entrada do contêiner.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# O comando para iniciar o Supervisor, que por sua vez iniciará o Nginx e o PHP-FPM.
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
