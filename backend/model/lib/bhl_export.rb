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
      :restriction_types => restriction_types(id)
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

  def restriction_types(resource_id)
    restriction_types = ArchivalObject.filter(:root_record_id => resource_id).
                        left_outer_join(:note, Sequel.qualify(:note, :archival_object_id) => Sequel.qualify(:archival_object, :id)).
                        left_outer_join(:rights_restriction, Sequel.qualify(:rights_restriction, :archival_object_id) => Sequel.qualify(:archival_object, :id)).
                        left_outer_join(:rights_restriction_type, Sequel.qualify(:rights_restriction_type, :rights_restriction_id) => Sequel.qualify(:rights_restriction, :id)).
                        select(
                          Sequel.as(Sequel.lit("BHL_GetEnumValue(rights_restriction_type.restriction_type_id)"), :restriction_types)
                        ).
                        where(Sequel.lit('LOWER(CONVERT(note.notes using utf8)) like "%accessrestrict%"')).
                        where(Sequel.qualify(:note, :publish) => 1).
                        where(Sequel.qualify(:archival_object, :publish) => 1).
                        map(:restriction_types)
    restriction_types.uniq
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