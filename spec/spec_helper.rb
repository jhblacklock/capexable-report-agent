require 'bundler/setup'
require 'rspec'
require 'rack/test'
require 'capybara/rspec'
require_relative '../app'

Capybara.app = Sinatra::Application
Sinatra::Application.environment = :test
Bundler.require :default, Sinatra::Application.environment

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include Capybara::DSL
end 