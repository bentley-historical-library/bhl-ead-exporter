module BhlExportHelpers

  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_bhl_ead(id, include_unpublished, include_daos, use_numbered_c_tags)
    resolve = ['repository', 'linked_agents', 'subjects', 'digital_object', 'top_container', 'top_container::container_profile']

    resource = Resource.get_or_die(id)

    jsonmodel = JSONModel(:resource).new(resolve_references(Resource.to_jsonmodel(resource), resolve))

    opts = {
      :include_unpublished => include_unpublished,
      :include_daos => include_daos,
      :use_numbered_c_tags => use_numbered_c_tags,
      :contains_university_restrictions => contains_university_restrictions(id)
    }
    ead = ASpaceExport.model(:bhl_ead).from_resource(jsonmodel, resource.tree(:all, mode = :sparse), opts)
    ASpaceExport::stream(ead)
  end

  def contains_university_restrictions(resource_id)
    restriction_counts = Resource.filter(:id => resource_id).
                          select(
                            Sequel.as(Sequel.lit('CountAccessrestrictByType(resource.id, "pr")'), :PR),
                            Sequel.as(Sequel.lit('CountAccessrestrictByType(resource.id, "sr")'), :SR),
                            Sequel.as(Sequel.lit('CountAccessrestrictByType(resource.id, "er")'), :ER),
                            Sequel.as(Sequel.lit('CountAccessrestrictByType(resource.id, "cr")'), :CR)
                            ).first

    if (restriction_counts[:PR] > 0) or (restriction_counts[:SR] > 0) or (restriction_counts[:ER] > 0) or (restriction_counts[:CR] > 0)
      true
    else
      false
    end
  end

  def generate_digitization_ead(id, include_unpublished, include_daos, use_numbered_c_tags)
    resolve = ['repository', 'linked_agents', 'subjects', 'digital_object', 'top_container', 'top_container::container_profile']

    resource = Resource.get_or_die(id)

    jsonmodel = JSONModel(:resource).new(resolve_references(Resource.to_jsonmodel(resource), resolve))

    opts = {
      :include_unpublished => include_unpublished,
      :include_daos => include_daos,
      :use_numbered_c_tags => use_numbered_c_tags
    }
    ead = ASpaceExport.model(:bhl_digitization).from_resource(jsonmodel, resource.tree(:all, mode = :sparse), opts)
    ASpaceExport::stream(ead)
  end

end