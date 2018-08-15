require 'spec_helper'

module Bosh::AwsCloud
  describe ResourceWait do
    before { allow(Kernel).to receive(:sleep) }

    describe '.for_instance' do
      let(:instance) { double(Aws::EC2::Instance, id: 'i-1234', data: 'some-data', exists?: true) }

      before do
        allow(instance).to receive(:reload)
      end

      context 'deletion' do
        it 'should wait until the state is terminated' do
          expect(instance).to receive(:state).and_return('shutting_down')
          expect(instance).to receive(:state).and_return('shutting_down')
          expect(instance).to receive(:state).and_return('terminated')

          described_class.for_instance(instance: instance, state: 'terminated')
        end
      end

      context 'creation' do
        context 'when EC2 fails to find an instance' do
          it 'should wait until the state is running' do
            expect(instance).to receive(:state).and_raise(Aws::EC2::Errors::InvalidInstanceIDNotFound.new(nil, 'not-found'))
            expect(instance).to receive(:state).and_return('pending')
            expect(instance).to receive(:state).and_return('running')

            described_class.for_instance(instance: instance, state: 'running')
          end
        end

        context 'when resource is not found' do
          it 'should wait until the state is running' do
            expect(instance).to receive(:state).and_raise(Aws::EC2::Errors::ResourceNotFound.new(nil, 'not-found'))
            expect(instance).to receive(:state).and_return('pending')
            expect(instance).to receive(:state).and_return('running')

            described_class.for_instance(instance: instance, state: 'running')
          end
        end

        context 'AWS terminates the instance' do
          it 'should fail if it wasn\'t terminated with /some matcher/' do
            expect(instance).to receive(:state).and_return('pending')
            expect(instance).to receive(:state).and_return('pending')
            expect(instance).to receive(:state).and_return('terminated')
            expect(instance).to receive(:state_reason).and_return(double("state_reason", message: 'bad things are afoot'))

            expect(ResourceWait.logger).to receive(:error).with(/state changed from 'starting' to 'terminated'/)
            expect {
              described_class.for_instance(instance: instance, state: 'running')
            }.to raise_error Bosh::Clouds::VMCreationFailed, /failed to create: state changed from 'starting' to 'terminated' with reason: 'bad things are afoot'/
          end

          it 'should raise Bosh::AwsCloud::AbruptlyTerminated' do
            expect(instance).to receive(:state).and_return('terminated')
            expect(instance).to receive(:state_reason).and_return(double("state_reason", message: 'Server.InternalError: Internal error on launch'))

            expect {
              described_class.for_instance(instance: instance, state: 'running')
            }.to raise_error Bosh::AwsCloud::AbruptlyTerminated, /Server.InternalError: Internal error on launch/
          end
        end
      end
    end

    describe '.for_attachment' do
      let(:volume) { double(Aws::EC2::Volume, id: 'vol-1234', data: 'some-data', exists?: true) }
      let(:instance) { double(Aws::EC2::Instance, id: 'i-5678', data: 'some-data', exists?: true) }
      let(:attachment) { double(SdkHelpers::VolumeAttachment, volume: volume, instance: instance, device: '/dev/sda1', data: 'some-data', exists?: true) }
      before do
        allow(attachment).to receive(:reload)
      end

      context 'attachment' do
        it 'should wait until the state is attached' do
          expect(attachment).to receive(:state).and_return('attaching')
          expect(attachment).to receive(:state).and_return('attached')

          described_class.for_attachment(attachment: attachment, state: 'attached')
        end

        it 'should retry when Aws::Core::Resource::NotFound is raised' do
          expect(attachment).to receive(:state).and_raise(Aws::EC2::Errors::ResourceNotFound.new(nil, 'not-found'))
          expect(attachment).to receive(:state).and_return('attached')

          described_class.for_attachment(attachment: attachment, state: 'attached')
        end
      end

      context 'detachment' do
        it 'should wait until the state is detached' do
          expect(attachment).to receive(:state).and_return('detaching')
          expect(attachment).to receive(:state).and_return('detached')

          described_class.for_attachment(attachment: attachment, state: 'detached')
        end

        it 'should consider Aws::Core::Resource::NotFound to be detached' do
          expect(attachment).to receive(:state).and_return('detaching')
          expect(attachment).to receive(:state).and_raise(Aws::EC2::Errors::ResourceNotFound.new(nil, 'not-found'))

          described_class.for_attachment(attachment: attachment, state: 'detached')
        end
      end
    end

    describe '.for_volume' do
      let(:volume) { double(Aws::EC2::Volume, id: 'v-123', data: 'some-data', exists?: true) }
      before do
        allow(volume).to receive(:reload)
      end


      context 'creation' do
        it 'should wait until the state is available' do
          expect(volume).to receive(:state).and_return('creating')
          expect(volume).to receive(:state).and_return('available')

          described_class.for_volume(volume: volume, state: 'available')
        end

        it 'should raise an error on error state' do
          expect(volume).to receive(:state).and_return('creating')
          expect(volume).to receive(:state).and_return('error')

          expect {
            described_class.for_volume(volume: volume, state: 'available')
          }.to raise_error Bosh::Clouds::CloudError, /state is error, expected available/
        end
      end

      context 'deletion' do
        it 'should wait until the state is deleted' do
          expect(volume).to receive(:state).and_return('deleting')
          expect(volume).to receive(:state).and_return('deleted')

          described_class.for_volume(volume: volume, state: 'deleted')
        end

        it 'should consider InvalidVolume error to mean deleted' do
          expect(volume).to receive(:state).and_return('deleting')
          expect(volume).to receive(:state).and_raise(Aws::EC2::Errors::InvalidVolumeNotFound.new(nil, 'not-found'))

          described_class.for_volume(volume: volume, state: 'deleted')
        end
      end
    end

    describe '.for_snapshot' do
      let(:snapshot) { double(Aws::EC2::Snapshot, id: 'snap-123', data: 'some-data', exists?: true) }
      before do
        allow(snapshot).to receive(:reload)
      end

      context 'creation' do
        it 'should wait until the state is completed' do
          expect(snapshot).to receive(:state).and_return('pending')
          expect(snapshot).to receive(:state).and_return('completed')

          described_class.for_snapshot(snapshot: snapshot, state: 'completed')
        end

        it 'should raise an error if the state is error' do
          expect(snapshot).to receive(:state).and_return('pending')
          expect(snapshot).to receive(:state).and_return('error')

          expect {
            described_class.for_snapshot(snapshot: snapshot, state: 'completed')
          }.to raise_error Bosh::Clouds::CloudError, /state is error, expected completed/
        end
      end
    end

    describe '.for_image' do
      let(:image) { double(Aws::EC2::Image, id: 'ami-123', data: 'some-data', exists?: true) }
      before do
        allow(image).to receive(:reload)
      end

      context 'creation' do
        it 'should wait until the state is available' do
          expect(image).to receive(:state).and_return('pending')
          expect(image).to receive(:state).and_return('available')

          described_class.for_image(image: image, state: 'available')
        end

        it 'should wait if Aws::EC2::Errors::InvalidAMIID::NotFound raised' do
          expect(image).to receive(:state).and_raise(Aws::EC2::Errors::InvalidAMIIDNotFound.new(nil, 'not-found'))
          expect(image).to receive(:state).and_return('pending')
          expect(image).to receive(:state).and_return('available')

          described_class.for_image(image: image, state: 'available')
        end

        it 'should raise an error if the state is failed' do
          expect(image).to receive(:state).and_return('pending')
          expect(image).to receive(:state).and_return('failed')

          expect {
            described_class.for_image(image: image, state: 'available')
          }.to raise_error Bosh::Clouds::CloudError, /state is failed, expected available/
        end
      end

      context 'deletion' do
        it 'should wait until the state is deregistered' do
          expect(image).to receive(:state).and_return('available')
          expect(image).to receive(:state).and_return('pending')
          expect(image).to receive(:state).and_return('deregistered')

          described_class.for_image(image: image, state: 'deregistered')
        end
      end
    end

    describe 'catching errors' do
      it 'raises an error if the retry count is exceeded' do
        resource = double('resource', state: 'bar', data: 'some-data', exists?: true)
        resource_arguments = {
          resource: resource,
          tries: 1,
          description: 'description',
          target_state: 'foo'
        }

        expect {
          subject.for_resource(resource_arguments) { |_| false }
        }.to raise_error(Bosh::Clouds::CloudError, /Timed out waiting/)
      end
    end

    describe '.sleep_callback' do
      it 'returns interval until max sleep time is reached' do
        scb = described_class.sleep_callback('fake-time-test', {interval: 5, total: 8})
        expected_times = [1, 6, 11, 15, 15, 15, 15, 15]
        returned_times = (0..7).map { |try_number| scb.call(try_number, nil) }
        expect(returned_times).to eq(expected_times)
      end

      it 'returns interval until tries_before_max is reached' do
        scb = described_class.sleep_callback('fake-time-test', {interval: 0, tries_before_max: 4, total: 8})
        expected_times = [1, 1, 1, 1, 15, 15, 15, 15]
        returned_times = (0..7).map { |try_number| scb.call(try_number, nil) }
        expect(returned_times).to eq(expected_times)
      end

      context 'when exponential sleep time is used' do
        it 'retries for 1, 2, 4, 8 up to max time' do
          scb = described_class.sleep_callback('fake-time-test', {interval: 2, total: 8, max: 32, exponential: true})
          expected_times = [1, 2, 4, 8, 16, 32, 32, 32]
          returned_times = (0..7).map { |try_number| scb.call(try_number, nil) }
          expect(returned_times).to eq(expected_times)
        end
      end
    end

    describe '#for_resource' do
      let(:fake_resource) { double('fake ec2 resource which has state method', state: 'unknown', reload: nil, data: 'some_data', exists?: true) }
      let(:args) do
        {
          resource: fake_resource,
          description: 'description',
          target_state: 'fake-target-state',
        }
      end

      it 'uses Bosh::Retryable with sleep_callback sleep setting' do
        sleep_cb = double('fake-sleep-callback')
        allow(described_class).to receive(:sleep_callback).and_return(sleep_cb)

        retryable = double('Bosh::Retryable', retryer: nil)
        expect(Bosh::Retryable)
          .to receive(:new)
          .with(hash_including(sleep: sleep_cb))
          .and_return(retryable)

        subject.for_resource(args)
      end

      context 'when the resource asynchronously ceases to exist' do
        let(:fake_resource) { double('fake ec2 resource which has state method', state: 'unknown', reload: nil, data: nil, exists?: false) }

        it 'raises a ResourceNotFound error' do
          expect { subject.for_resource(args) }.to raise_error(Aws::EC2::Errors::ResourceNotFound)
        end
      end

      context 'when we exceed request limit' do
        let(:instance) { double(Aws::EC2::Instance, id: 'i-1234', data: 'some-data', exists?: true) }

        before do
          allow(instance).to receive(:reload)
          call_count = 0
          allow(instance).to receive(:state) do
            case call_count += 1
            when 1
              'running'
            when 2
              raise Aws::EC2::Errors::RequestLimitExceeded.new(nil, 'error')
            else
              'terminated'
            end
          end
        end

        it 'rescues the error and retries after a backoff' do
          described_class.for_instance(instance: instance, state: 'terminated')
          expect(instance).to have_received(:state).exactly(3).times
        end
      end

      context 'when tries option is passed' do
        before { args[:tries] = 5 }

        it 'attempts passed number of times' do
          actual_attempts = 0
          expect {
            subject.for_resource(args) { actual_attempts += 1; false }
          }.to raise_error(/Timed out waiting for description/)
          expect(actual_attempts).to eq(5)
        end
      end

      context 'when tries option is not passed' do
        it 'attempts DEFAULT_TRIES times to wait for ~25 minutes' do
          actual_attempts = 0
          expect {
            subject.for_resource(args) { actual_attempts += 1; false }
          }.to raise_error(/Timed out waiting for description/)
          expect(actual_attempts).to eq(54)
        end
      end
    end
  end
end
