require_relative "../model/lib/bhl_export"
class ArchivesSpaceService < Sinatra::Base

  include BhlExportHelpers

  Endpoint.get('/repositories/:repo_id/bhl_resource_descriptions/:id.xml')
    .description("Get an EAD representation of a Resource")
    .params(["id", :id],
            ["include_unpublished", BooleanParam,
             "Include unpublished records", :optional => true],
            ["include_daos", BooleanParam,
             "Include digital objects in dao tags", :optional => true],
            ["numbered_cs", BooleanParam,
             "Use numbered <c> tags in ead", :optional => true],
            ["print_pdf", BooleanParam,
             "Print EAD to pdf", :optional => true],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "(:resource)"]) \
  do
    redirect to("/repositories/#{params[:repo_id]}/resource_descriptions/#{params[:id]}.pdf?#{ params.map { |k,v| "#{k}=#{v}" }.join("&") }") if params[:print_pdf] 
    ead_stream = generate_bhl_ead(params[:id],
                              (params[:include_unpublished] || false),
                              (params[:include_daos] || false),
                              (params[:numbered_cs] || false))

    stream_response(ead_stream)
  end

end