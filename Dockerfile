FROM ruby:3.4-slim

# Dépendances système
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      curl \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Installation des gems (cache optimisé)
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copie du code
COPY . .

# Précompilation des assets (en production)
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
