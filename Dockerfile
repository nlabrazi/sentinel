FROM ruby:3.4-slim

ENV BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3"

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libpq-dev \
      libyaml-dev \
      curl \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install
RUN chmod -R a+rwX /bundle

COPY . .

# Précompilation des assets Tailwind pour rendre l'image autonome et prête à l'exécution
RUN SECRET_KEY_BASE=dummy-key-for-assets bin/rails tailwindcss:build

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
