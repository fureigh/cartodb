require_relative '../spec_helper'

require_relative '../../app/models/visualization/collection'

include CartoDB

describe Organization do

  before(:all) do
    @user = create_user(:quota_in_bytes => 524288000, :table_quota => 500)
  end

  after(:all) do
    Visualization::Member.any_instance.stubs(:has_named_map?).returns(false)
    @user.destroy
  end

  describe '#add_user_to_org' do
    it 'Tests adding a user to an organization' do
      org_name = 'wadus'
      org_quota = 1234567890
      org_seats = 5

      username = @user.username

      organization = Organization.new

      organization.name = org_name
      organization.quota_in_bytes = org_quota
      organization.seats = org_seats
      organization.save
      organization.valid?.should eq true
      organization.errors.should eq Hash.new

      @user.organization = organization
      @user.save

      user = User.where(username: username).first
      user.should_not be nil

      user.organization_id.should_not eq nil
      user.organization_id.should eq organization.id
      user.organization.should_not eq nil
      user.organization.id.should eq organization.id
      user.organization.name.should eq org_name
      user.organization.quota_in_bytes.should eq org_quota
      user.organization.seats.should eq org_seats

      @user.organization = nil
      @user.save
      organization.destroy
    end
  end

  describe '#unique_name' do
    it 'Tests uniqueness of name' do
      org_name = 'wadus'

      organization = Organization.new
      organization.name = org_name
      organization.quota_in_bytes = 123
      organization.seats = 1
      organization.errors
      organization.valid?.should eq true

      # Repeated username
      organization.name = @user.username
      organization.valid?.should eq false
      organization.name = org_name
      organization.save

      organization2 = Organization.new
      # Repeated name
      organization2.name = org_name
      organization2.quota_in_bytes = 123
      organization2.seats = 1
      organization2.valid?.should eq false

      organization.destroy
    end
  end

  describe '#org_shared_vis' do
    it "checks fetching all shared visualizations of an organization's members " do
      CartoDB::NamedMapsWrapper::NamedMaps.any_instance.stubs(:get).returns(nil)
      # Don't check/handle DB permissions
      Permission.any_instance.stubs(:revoke_previous_permissions).returns(nil)
      Permission.any_instance.stubs(:grant_db_permission).returns(nil)

      vis_1_name = 'viz_1'
      vis_2_name = 'viz_2'
      vis_3_name = 'viz_3'

      user1 = create_user(:quota_in_bytes => 1234567890, :table_quota => 5)
      user2 = create_user(:quota_in_bytes => 1234567890, :table_quota => 5)
      user3 = create_user(:quota_in_bytes => 1234567890, :table_quota => 5)

      organization = Organization.new
      organization.name = 'qwerty'
      organization.seats = 5
      organization.quota_in_bytes = 1234567890
      organization.save.reload
      user1.organization_id = organization.id
      user1.save.reload
      organization.owner_id = user1.id
      organization.save.reload
      user2.organization_id = organization.id
      user2.save.reload
      user3.organization_id = organization.id
      user3.save.reload

      vis1 = Visualization::Member.new(random_attributes(name: vis_1_name, user_id: user1.id)).store
      vis2 = Visualization::Member.new(random_attributes(name: vis_2_name, user_id: user2.id)).store
      vis3 = Visualization::Member.new(random_attributes(name: vis_3_name, user_id: user3.id)).store

      perm = vis1.permission
      perm.acl = [
          {
              type: Permission::TYPE_ORGANIZATION,
              entity: {
                  id:       organization.id,
                  username: organization.name
              },
              access: Permission::ACCESS_READONLY
          }
      ]
      perm.save

      perm = vis2.permission
      perm.acl = [
          {
              type: Permission::TYPE_ORGANIZATION,
              entity: {
                  id:       organization.id,
                  username: organization.name
              },
              access: Permission::ACCESS_READONLY
          }
      ]
      perm.save

      perm = vis3.permission
      perm.acl = [
          {
              type: Permission::TYPE_ORGANIZATION,
              entity: {
                  id:       organization.id,
                  username: organization.name
              },
              access: Permission::ACCESS_READONLY
          }
      ]
      perm.save

      # Setup done, now to the proper test

      org_vis_array = organization.public_visualizations.map { |vis|
        vis.id
      }
      # Order is newest to oldest
      org_vis_array.should eq [vis3.id, vis2.id, vis1.id]

      # Clear first shared entities to be able to destroy
      vis1.permission.acl = []
      vis1.permission.save
      vis2.permission.acl = []
      vis2.permission.save
      vis3.permission.acl = []
      vis3.permission.save

      begin
        user2.destroy
        user3.destroy
        user1.destroy
      rescue
        # TODO: Finish deletion of organization users and remove this so users are properly deleted or test fails
      end
    end
  end

  describe "#get_api_calls and #get_geocodings" do
    before(:each) do
      @organization = create_organization_with_users(name: 'overquota-org')
    end
    after(:each) do
      @organization.destroy
    end
    it "should return the sum of the api_calls for all organization users" do
      User.any_instance.stubs(:get_api_calls).returns (0..30).to_a
      @organization.get_api_calls.should == (0..30).to_a.sum * @organization.users.size
    end
    it "should return the sum of the geocodings for all organization users" do
      User.any_instance.stubs(:get_geocoding_calls).returns(30)
      @organization.get_geocoding_calls.should == 30 * @organization.users.size
    end
  end

  describe '.overquota', focus: true do
    before(:all) do
      @organization = create_organization_with_users(name: 'overquota-org')
    end
    after(:all) do
      @organization.destroy
    end
    it "should return organizations over their map view quota" do
      Organization.overquota.should be_empty
      Organization.any_instance.stubs(:get_api_calls).returns(30)
      Organization.any_instance.stubs(:map_view_quota).returns(10)
      Organization.overquota.map(&:id).should include(@organization.id)
      Organization.overquota.size.should == Organization.count
    end

    it "should return organizations over their geocoding quota" do
      Organization.overquota.should be_empty
      Organization.any_instance.stubs(:get_api_calls).returns(0)
      Organization.any_instance.stubs(:map_view_quota).returns(10)
      Organization.any_instance.stubs(:get_geocoding_calls).returns 30
      Organization.any_instance.stubs(:geocoding_quota).returns 10
      Organization.overquota.map(&:id).should include(@organization.id)
      Organization.overquota.size.should == Organization.count
    end

    it "should return organizations near their map view quota" do
      Organization.any_instance.stubs(:get_api_calls).returns(81)
      Organization.any_instance.stubs(:map_view_quota).returns(100)
      Organization.overquota.should be_empty
      Organization.overquota(0.20).map(&:id).should include(@organization.id)
      Organization.overquota(0.20).size.should == Organization.count
      Organization.overquota(0.10).should be_empty
    end

    it "should return organizations near their geocoding quota" do
      Organization.any_instance.stubs(:get_api_calls).returns(0)
      Organization.any_instance.stubs(:map_view_quota).returns(120)
      Organization.any_instance.stubs(:get_geocoding_calls).returns(81)
      Organization.any_instance.stubs(:geocoding_quota).returns(100)
      Organization.overquota.should be_empty
      Organization.overquota(0.20).map(&:id).should include(@organization.id)
      Organization.overquota(0.20).size.should == Organization.count
      Organization.overquota(0.10).should be_empty
    end
  end


  def random_attributes(attributes={})
    random = rand(999)
    {
        name:         attributes.fetch(:name, "name #{random}"),
        description:  attributes.fetch(:description, "description #{random}"),
        privacy:      attributes.fetch(:privacy, Visualization::Member::PRIVACY_PUBLIC),
        tags:         attributes.fetch(:tags, ['tag 1']),
        type:         attributes.fetch(:type, Visualization::Member::DERIVED_TYPE),
        user_id:      attributes.fetch(:user_id, UUIDTools::UUID.timestamp_create.to_s)
    }
  end #random_attributes

end
