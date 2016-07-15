class BhlexportsController < ApplicationController

  set_access_control  "view_repository" => [:download_bhl_ead]

  include ExportHelper

  def download_bhl_ead
    url = "/repositories/#{JSONModel::repository}/bhl_resource_descriptions/#{params[:id]}.xml"
    
    download_export(url,
                    :include_unpublished => (params[:include_unpublished] ? params[:include_unpublished] : false),
                    :print_pdf => (params[:print_pdf] ? params[:print_pdf] : false),
                    :include_daos => (params[:include_daos] ? params[:include_daos] : false),
                    :numbered_cs => (params[:numbered_cs] ? params[:numbered_cs] : false))
  end
end