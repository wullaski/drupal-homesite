FROM php:8.3-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libwebp-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    zip \
    unzip \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions with GD support for WebP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip opcache

# Enable Apache modules
RUN a2enmod rewrite headers expires

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html

# Install PHP dependencies at build time so the image is self-contained.
# allow-plugins are already declared in composer.json, so no runtime config is needed.
RUN composer install --no-dev --no-interaction --optimize-autoloader --no-progress

# Normalise ownership only. Composer already sets sane permissions (binaries
# executable, everything else readable), so we deliberately do NOT run a blanket
# `chmod` here: it would strip the execute bit from vendor binaries like drush,
# and forking one chmod per file across the whole tree takes minutes. A single
# recursive chown is fast and leaves execute bits intact.
RUN chown -R www-data:www-data /var/www/html

# Apache configuration
RUN echo '<VirtualHost *:80>\n\
    ServerAdmin webmaster@localhost\n\
    DocumentRoot /var/www/html/web\n\
    <Directory /var/www/html/web>\n\
        Options -Indexes +FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
    ErrorLog ${APACHE_LOG_DIR}/error.log\n\
    CustomLog ${APACHE_LOG_DIR}/access.log combined\n\
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

EXPOSE 80

CMD ["apache2-foreground"]
