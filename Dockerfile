# Usa a imagem base do PHP com FPM para a versão 8.2
FROM php:8.2-fpm

# Define o diretório de trabalho dentro do contêiner
WORKDIR /var/www/html

# Instala as dependências do sistema e extensões PHP necessárias
# Inclui git, unzip, libpq-dev (para PostgreSQL), libpng-dev, libjpeg-dev, libzip-dev
# e outras extensões PHP comuns para aplicações Laravel.
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
    && rm -rf /var/lib/apt/lists/*

# Instala as extensões PHP
RUN docker-php-ext-install pdo pdo_pgsql zip gd

# Instala o Composer
# Baixa o instalador do Composer, verifica sua integridade e move para /usr/local/bin
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Copia os arquivos da aplicação para o diretório de trabalho
# O .dockerignore deve ser configurado para excluir o diretório vendor e node_modules
COPY . .

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

# Copia a configuração do Nginx
# Assume que você tem um arquivo nginx.conf no diretório docker/nginx.conf
COPY docker/nginx.conf /etc/nginx/sites-available/default

# Remove a configuração padrão do Nginx e cria um link simbólico para a nova configuração
RUN rm /etc/nginx/sites-enabled/default \
    && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Copia a configuração do Supervisor
# Assume que você tem um arquivo supervisord.conf no diretório docker/supervisord.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expõe a porta 80 para acesso via HTTP
EXPOSE 80

# Inicia o Supervisor, que por sua vez iniciará o Nginx e o PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
