require 'integration/spec_helper'
require 'logger'
require 'cloud'
require 'open-uri'

describe Bosh::AwsCloud::CloudV1 do
  let(:logger) { Bosh::Cpi::Logger.new(STDERR) }
  let(:non_existent_vm_id) { 'i-010fd20eb24f606ab' }

  describe 'specifying ec2 endpoint instead of region' do
    let(:cpi) do
      Bosh::AwsCloud::CloudV1.new(
        'aws' => {
          'ec2_endpoint' => 'https://ec2.sa-east-1.amazonaws.com',
          'elb_endpoint' => 'https://elasticloadbalancing.sa-east-1.amazonaws.com',
          'region' => 'sa-east-1',
          'access_key_id' => @access_key_id,
          'default_key_name' => 'fake-key',
          'secret_access_key' => @secret_access_key,
          'session_token' => @session_token,
          'max_retries' => 8
        },
        'registry' => {
          'endpoint' => 'fake',
          'user' => 'fake',
          'password' => 'fake'
        }
      )
    end

    it 'uses the given endpoint' do
      expect {
        cpi.has_vm?(non_existent_vm_id)
      }.to_not raise_error
    end

    context 'endpoint does not match region' do
      let(:cpi) do
        Bosh::AwsCloud::CloudV1.new(
          'aws' => {
            'ec2_endpoint' => 'https://ec2.fake-endpoint.amazonaws.com',
            'region' => 'sa-east-1',
            'access_key_id' => @access_key_id,
            'default_key_name' => 'fake-key',
            'secret_access_key' => @secret_access_key,
            'session_token' => @session_token,
            'max_retries' => 8
          },
          'registry' => {
            'endpoint' => 'fake',
            'user' => 'fake',
            'password' => 'fake'
          }
        )
      end

      it 'raises an error' do
        expect {
          cpi.has_vm?(non_existent_vm_id)
        }.to raise_error(/fake-endpoint/)
      end
    end
  end

  describe 'specifying elb endpoint instead of region' do
    context 'endpoint does not match region' do
      let(:cpi) do
        Bosh::AwsCloud::CloudV1.new(
          'aws' => {
            'elb_endpoint' => 'https://elasticloadbalancing.fake-endpoint.amazonaws.com',
            'region' => 'sa-east-1',
            'access_key_id' => @access_key_id,
            'default_key_name' => 'fake-key',
            'secret_access_key' => @secret_access_key,
            'session_token' => @session_token,
            'max_retries' => 8
          },
          'registry' => {
            'endpoint' => 'fake',
            'user' => 'fake',
            'password' => 'fake'
          }
        )
      end

      context 'when using ALBs' do
        let(:vm_type) do
          {
            'lb_target_groups' => ['fake-target-group']
          }
        end

        it 'raises an error' do
          expect {
            cpi.create_vm(
              'test-id',
              nil,
              vm_type,
              nil,
              nil,
              nil,
            )
          }.to raise_error(/fake-endpoint/)
        end
      end

      context 'when using ELBs' do
        let(:vm_type) do
          {
            'elbs' => ['fake-elb']
          }
        end

        it 'raises an error' do
          expect {
            cpi.create_vm(
              'test-id',
              nil,
              vm_type,
              nil,
              nil,
              nil
            )
          }.to raise_error(/fake-endpoint/)
        end
      end
    end
  end

  describe 'using a custom CA bundle' do
    let(:cpi) do
      Bosh::AwsCloud::CloudV1.new(
        'aws' => {
          'region' => @region,
          'default_key_name' => 'fake-key',
          'access_key_id' => @access_key_id,
          'secret_access_key' => @secret_access_key,
          'session_token' => @session_token,
          'max_retries' => 8
        },
        'registry' => {
          'endpoint' => 'fake',
          'user' => 'fake',
          'password' => 'fake'
        }
      )
    end

    before(:example) do
      @original_cert_file = ENV['BOSH_CA_CERT_FILE']
    end

    after(:example) do
      if @original_cert_file.nil?
        ENV.delete('BOSH_CA_CERT_FILE')
      else
        ENV['BOSH_CA_CERT_FILE'] = @original_cert_file
      end
    end

    before(:each) { ENV.delete('BOSH_CA_CERT_FILE') }

    context 'when the certificate returned from the server contains a CA in the provided bundle' do
      it 'completes requests over SSL' do
        begin
          valid_bundle = File.open('valid-ca-bundle', 'w+') do |f|
            # Download the CA bundle that is included in the AWS SDK
            f << open('https://raw.githubusercontent.com/aws/aws-sdk-ruby/v2.10.39/aws-sdk-core/ca-bundle.crt').read
          end

          ENV['BOSH_CA_CERT_FILE'] = valid_bundle.path

          expect {
            cpi.has_vm?(non_existent_vm_id)
          }.to_not raise_error
        ensure
          File.delete(valid_bundle.path)
        end

      end
    end

    context 'when the certificate returned from the server does not contain a CA in the provided bundle' do
      it 'raises an SSL verification error' do
        ENV['BOSH_CA_CERT_FILE'] = asset('invalid-cert.pem')

        expect {
          cpi.has_vm?(non_existent_vm_id)
        }.to raise_error(/endpoint/i)
      end
    end

    context 'when the endpoint is provided without a protocol' do
      let(:cpi) do
        Bosh::AwsCloud::CloudV1.new(
          'aws' => {
            'ec2_endpoint' => 'ec2.sa-east-1.amazonaws.com',
            'elb_endpoint' => 'elasticloadbalancing.sa-east-1.amazonaws.com',
            'region' => 'sa-east-1',
            'access_key_id' => @access_key_id,
            'default_key_name' => 'fake-key',
            'secret_access_key' => @secret_access_key,
            'session_token' => @session_token,
            'max_retries' => 8
          },
          'registry' => {
            'endpoint' => 'fake',
            'user' => 'fake',
            'password' => 'fake'
          }
        )
      end

      it 'auto-applies a protocol and uses the given endpoint' do
        expect {
          cpi.has_vm?(non_existent_vm_id)
        }.to_not raise_error
      end
    end
  end
end
