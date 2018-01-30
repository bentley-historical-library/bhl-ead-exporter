module BhlExportHelpers

  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_bhl_ead(id, include_unpublished, include_daos, use_numbered_c_tags, ead3)
    resolve = ['repository', 'linked_agents', 'subjects', 'digital_object', 'top_container', 'top_container::container_profile']

    resource = Resource.get_or_die(id)

    jsonmodel = JSONModel(:resource).new(resolve_references(Resource.to_jsonmodel(resource), resolve))

    opts = {
      :include_unpublished => include_unpublished,
      :include_daos => include_daos,
      :use_numbered_c_tags => use_numbered_c_tags,
      :ead3 => ead3,
      :contains_university_restrictions => contains_university_restrictions(id)
    }

    if ead3
      opts[:serializer] = :ead3
      model = :ead
    else
      model = :bhl_ead
    end

    ead = ASpaceExport.model(model).from_resource(jsonmodel, resource.tree(:all, mode = :sparse), opts)
    ASpaceExport::stream(ead)
  end

  def contains_university_restrictions(resource_id)
    university_restrictions = ArchivalObject.filter(:root_record_id => resource_id).
                          left_outer_join(:note, :archival_object_id => Sequel.qualify(:archival_object, :id)).
                          where(Sequel.lit('LOWER(CONVERT(note.notes using utf8)) LIKE "%accessrestrict%"')).
                          where(Sequel.lit('LOWER(CONVERT(note.notes using utf8)) LIKE "%sr restrict%" 
                            OR LOWER(CONVERT(note.notes using utf8)) LIKE "%pr restrict%" 
                            OR LOWER(CONVERT(note.notes using utf8)) LIKE "%er restrict%" 
                            OR LOWER(CONVERT(note.notes using utf8)) LIKE "%cr restrict%"')).count

    if university_restrictions > 0
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