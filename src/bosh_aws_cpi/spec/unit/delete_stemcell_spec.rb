# Copyright (c) 2009-2012 VMware, Inc.

require 'spec_helper'

describe Bosh::AwsCloud::CloudV1 do
  it 'should delete the stemcell' do
    stemcell = double(Bosh::AwsCloud::Stemcell)

    cloud = mock_cloud do |ec2|
      allow(Bosh::AwsCloud::StemcellFinder).to receive(:find_by_id).with(ec2, 'ami-xxxxxxxx').and_return(stemcell)
    end

    expect(stemcell).to receive(:delete)

    cloud.delete_stemcell('ami-xxxxxxxx')
  end
end
