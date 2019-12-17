class Resource < ActiveRecord::Base
  include ::Resourceconcern

  has_many :types, dependent: :destroy
  has_many :audiences, dependent: :destroy
  has_many :client_tags, dependent: :destroy
  has_many :population_focuses, dependent: :destroy
  has_many :campuses, dependent: :destroy
  has_many :colleges, dependent: :destroy
  has_many :availabilities, dependent: :destroy
  has_many :innovation_stages, dependent: :destroy
  has_many :topics, dependent: :destroy
  has_many :technologies, dependent: :destroy
  after_destroy :destroy_related_records
  # validations: https://guides.rubyonrails.org/active_record_validations.html
  validates :title, :url, :location, presence: true
  validates :description, presence: true#, :length => {:maximum => 500}
  # TODO: figure out if a character limit is needed since certain descriptions in the original spread sheet have above 500 characters (ex: CITRIS Foundry)

  def self.auth_params
    [:flagged, :approval_status, :approved_by]
  end

  def self.include_has_many_params
    {
        types: {only: [:val]},
        audiences: {only: [:val]},
        client_tags: {only: [:val]},
        population_focuses: {only: [:val]},
        campuses: {only: [:val]},
        colleges: {only: [:val]},
        availabilities: {only: [:val]},
        innovation_stages: {only: [:val]},
        topics: {only: [:val]},
        technologies: {only: [:val]}
    }
  end

  def self.guest_update_params_allowed?(resource_params)
    update_allowed = (((resource_params.keys.size <= 1) and
        (resource_params.keys[0] == 'flagged') and (resource_params['flagged'] == 1)) or
        ((resource_params.keys[0] == 'flagged' or resource_params.keys[0] == 'flagged_comment') and
            (resource_params.keys[1] == 'flagged' or resource_params.keys[1] == 'flagged_comment') and resource_params['flagged'] == 1))
    update_allowed
  end

  # returns a list of all associations [:types, :audiences, :client_tags, :population_focuses, :campuses, ...]
  def self.has_many_associations
    Resource.reflect_on_all_associations(:has_many).map! { |association| association.name.to_sym }
  end

  def self.get_associations_hash(resource)
    {audiences: resource.audiences, availabilities: resource.availabilities,
     campuses: resource.campuses, client_tags: resource.client_tags,
     colleges: resource.colleges, innovation_stages: resource.innovation_stages,
     population_focuses: resource.population_focuses, technologies: resource.technologies,
     topics: resource.topics, types: resource.types
    }
  end

  # finds the resources that match the filters provided
  def self.filter(params)
    params = params.to_h.map {|k,v| [k.to_sym, v]}.to_h # convert ActiveRecord::Controller params into hash with symbol keys
    # Partition params into has_many fields and normal fields
    # has_many_hash = {k => [v1,v2,v3]} ; ex. {audiences => [undergrad, grad, alumni]}
    has_many_hash = {}
    params.each_key do |key|
      if has_many_associations.include?(key)
        # String variation (JSON request)
        if params[key].is_a?(String)
          has_many_hash[key] = params[key].split(',').map { |x| x.strip } # split by comma delimiter, and strip leading and trailing whitespace
          # List variation (HTML request)
        elsif params[key].is_a?(Array)
          has_many_hash[key] = params[key]
        end
        params.delete(key) # remove has_many key from params
      end

    end

    # return early if there are no has_many fields
    search_regex = ''
    if params[:search].to_s.length != 0
      search_regex = "title ~* '.*" + params[:search].to_s + ".*'" + " OR description ~* '.*" + params[:search].to_s + ".*'"  + " OR url ~* '.*" + params[:search].to_s + ".*'"
    end
    params.delete :search
    if has_many_hash.empty?
      return Resource.where(params).where(search_regex)
    else
      resources = Resource.where(params).where(search_regex).includes(*Resource.has_many_associations)
      return filter_has_many_helper(resources, has_many_hash)
    end
  end

  # helps find resources based on that have multiple, specific associations
  def self.filter_has_many_helper(resources, has_many_hash)
    filtered = [] # list of returned records
    resources.find_each do |resource|
      associations_hash = get_associations_hash(resource)
      bool_arr = []
      # for each has_many query, check if the current record's has_many field contains all values in the query
      has_many_hash.each do |field, values|
        bool_arr.append (associations_hash[field].records.collect(&:val) & values).sort == values.sort
      end
      # if all queries return true, append the record to the returned value
      filtered.append resource if bool_arr.all?
    end
    # return ActiveRecord::Relation instead of array so that ActiveRecord calls can be chained outside this function
    Resource.where(id: filtered.map(&:id))
  end

  #
  def self.cast_param_vals(params)
    params.values_at(
        :flagged_comment,:title,:url,:location)
        .compact.each { |field| params[field] = params[field].to_s }
    if params[:flagged]
      params[:flagged] = params[:flagged].to_i
      params[:flagged] = 1 if params[:flagged] < 0 || params[:flagged] > 1
    end

    if params[:approval_status]
      params[:approval_status] = params[:approval_status].to_i
      if params[:approval_status] < 0 || params[:approval_status] > 2
        params[:approval_status] = 0
      end
    end

    params
  end

  def self.log_edits(params)
    # if the field exists, then create and Edit
    params.values_at(
        :flagged,:approval_status,:title,:url,:location)
        .compact.each { |field| edit_helper(params[:id], field) }
  end

  def self.edit_helper(id, param)
    @edit = Edit.new(resource_id: id, user: @user, parameter: param)
    @edit.save!
  end

  def self.create_resource(params)
    params, resource_hash = Resource.separate_params(params)

    resource = Resource.create(resource_hash)
    Resource.create_associations(resource, params) if resource.valid?

    resource
  end

  def self.update_resource(id, params)
    params, resource_hash = Resource.separate_params(params)

    resource = Resource.update(id, resource_hash)
    Resource.create_associations(resource, params)
    resource
  end

  def destroy_related_records
    types.each do |audience|
      types.destroy
    end
    audiences.each do |audience|
      audience.destroy
    end
    client_tags.each do |audience|
      client_tags.destroy
    end
    population_focuses.each do |audience|
      population_focuses.destroy
    end
    campuses.each do |audience|
      campuses.destroy
    end
    colleges.each do |audience|
      colleges.destroy
    end
    availabilities.each do |audience|
      availabilities.destroy
    end
    innovation_stages.each do |audience|
      innovation_stages.destroy
    end
    topics.each do |audience|
      topics.destroy
    end
    technologies.each do |audience|
      technologies.destroy
    end
  end

  def self.separate_params(params)
    params = params.to_h.map {|k,v| [k.to_sym, v]}.to_h
    resource_hash = {}
    params.each do |field, val|
      if has_many_associations.include? field
        params[field] = val.split(',') if val.is_a?(String)
      else
        params.delete field
        resource_hash[field] = val
      end
    end
    [params, resource_hash]
  end

  def self.create_associations(resource, params)
    fields_hash = get_associations_hash(resource)

    fields_hash.each do |field, association|
      association.delete_all # if updating, need to delete and remake associations
      if params[field] != nil
        params[field].each do |val|
          association.create!(val: val)
        end
      end
    end
  end

  def self.find_missing_params(params)
    missing = []
    Resource.get_required_resources.each do |r|
      missing.append r if !params.include?(r) or params[r] == ''
    end
    missing
  end

  # if filtering by location, filtering should behave as the following
  # find resources of location as well as its children
  # if the location has no resources, find the parent location, and return resources for the parent location
  def self.location_helper(params)

    location = params[:location]
    if location.nil? || !Location.where(val: location).exists?
      return filter(params)
    end

    locations = Location.child_locations(location)
    resources = Resource.none
    locations.each do |location|
      params[:location] = location
      resources = resources.or(filter(params))
    end

    # if resources.length < 1
    #   # get parent and its resources
    #   parent = Location.get_parent(location)
    #   locations = Location.child_locations(parent)
    #   resources = Resource.none

    #   locations.each do |location|
    #     params[:location] = location
    #     resources = resources.or(self.filter(params))
    #   end
    # end
    resources
  end

  def num_weeks_passed_column?(column, num)
    if column == 'last_email_sent'
      TimeDifference.between(last_email_sent, Time.now).in_weeks >= num
    elsif column == 'expired_last'
      TimeDifference.between(expired_last, Time.now).in_weeks >= num
    elsif column == 'approval_last'
      TimeDifference.between(approval_last, Time.now).in_weeks >= num
    elsif column == 'broken_last'
      TimeDifference.between(broken_last, Time.now).in_weeks >= num
    end
  end

  def not_updated_in_a_year?
    TimeDifference.between(updated_at, Time.now).in_years >= 1
  end

  def expired?
    !deadline.blank? && deadline < Time.now
  end

  def update_column_no_timestamp(column, value)
    Resource.record_timestamps = false
    update_column(column, value)
    Resource.record_timestamps = true
  end

  def isURLBroken_ifSoTagIt
    open(url) do |f|
      print 'GOOD URL' if f.status[1] == 'OK'
    end
  rescue StandardError => e
    print 'BAD URL'
    Resource.tagBrokenURL(id)
  end

  def self.tagBrokenURL(id)
    resource = Resource.find_by(id: id)
    isBrokenURLAlreadyTagged = false
    resource.types.as_json.each do |type|
      isBrokenURLAlreadyTagged = true if type['val'] == 'BrokenURL'
    end
    resource.types.create!(val: 'BrokenURL') unless isBrokenURLAlreadyTagged
    Resource.broken_url_email(resource)
  end


  def self.untagBrokenURL(id)
    resource = Resource.find_by(id: id)

    isBrokenURLAlreadyTagged=false
    resource.types.as_json.each do |type|
      if type['val']=='BrokenURL'
        isBrokenURLAlreadyTagged=true
      end
    end

    if isBrokenURLAlreadyTagged
      resource.types.find_by(:val => 'BrokenURL').destroy #deleting BrokenURL type
    end
    #puts resource.types.as_json
  end
end
