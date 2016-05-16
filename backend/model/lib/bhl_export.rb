module BhlExportHelpers

  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_bhl_ead(id, include_unpublished, include_daos, use_numbered_c_tags)
    obj = resolve_references(Resource.to_jsonmodel(i
      :include_unpublished => include_unpublished,
      :include_daos => include_daos,
      :use_numbered_c_tags => use_numbered_c_tagsd), ['repository', 'linked_agents', 'subjects', 'tree', 'digital_object'])
    opts = {
    }

    ead = ASpaceExport.model(:bhl_ead).from_resource(JSONModel(:resource).new(obj), opts)
    ASpaceExport::stream(ead)
  end

end