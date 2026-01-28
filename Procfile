# Procfile for Railway/Heroku deployment
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
telegram: bundle exec rake telegram:bot
