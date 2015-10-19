require 'spec_helper'
require 'yaml'
require 'hiera/backend/consul_backend'

class Hiera
  module Backend
    describe Consul_backend do
      include_context 'spec_root'

      context 'with a basic config' do
        before do
          path = File.join(spec_root, 'fixtures', 'hiera.yaml')
          config = YAML.load_file(path)

          Hiera::Config.load(config)
          stub_request(:get, "http://127.0.0.1:8500/v1/catalog/services").
            with(:headers => {'Accept'=>'*/*'}).
            to_return(:status => 200, :body => '[{"Node":"estpcsm4","Address":"10.195.121.10","ServiceID":"consul","ServiceName":"consul","ServiceTags":[],"ServiceAddress":"","ServicePort":8300}]', :headers => {})
        end

        describe '#initialize' do
          it 'should build the cache' do
            Consul_backend.new
          end

          it 'should not use ssl if ssl is not explicitly enabled' do
            Consul_backend.new

            expect(subject.consul).to be_a(Net::HTTP)
            expect(subject.consul.use_ssl?).to be(false)
          end
        end

        describe '#lookup' do
          before do
            Consul_backend.new
            stub_request(:get, "http://127.0.0.1:8500/v1/kv/configuration/test.example.com/test").
              with(:headers => {'Accept'=>'*/*'}).
              to_return(:status => 404, :body => "", :headers => {})

            stub_request(:get, "http://127.0.0.1:8500/v1/kv/configuration/common/test").
              with(:headers => {'Accept'=>'*/*'}).
              to_return(:status => 200, :body => '[{"CreateIndex":20,"ModifyIndex":20,"LockIndex":0,"Key":"configuration/common/test","Flags":0,"Value":"dGVzdGluZw=="}]', :headers => {})
          end

          it 'should break if an answer is found' do
            lookup = Backend.lookup('test', nil, {'::fqdn' => 'test.example.com'}, nil, :priority)
            expect(lookup).to eq('testing')
          end

        end

      end
    end
  end
end
