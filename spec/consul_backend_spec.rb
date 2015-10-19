require 'spec_helper'
require 'hiera/backend/consul_backend'

class Hiera
  module Backend
    describe Consul_backend do
      before do
        Hiera.stubs(:debug)
        Hiera.stubs(:warn)

        let(:config) do
          path = File.join(File.dirname(__FILE__), 'fixtures', 'hiera.yaml')
          YAML.load_file(path)
        end

        Hiera::Config.load(config)
      end

      describe '#lookup' do
      end
    end
  end
end
