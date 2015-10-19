require 'hiera'
require 'mocha'
require 'webmock/rspec'

RSpec.configure do |config|
  config.mock_with :mocha
end

shared_context 'spec_root' do
    let(:spec_root) { File.dirname(__FILE__) }
end
