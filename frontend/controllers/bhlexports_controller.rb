class BhlexportsController < ApplicationController

  set_access_control  "view_repository" => [:download_bhl_ead]

  include ExportHelper

  def download_bhl_ead
    url = "/repositories/#{JSONModel::repository}/bhl_resource_descriptions/#{params[:id]}.xml"
    metadata_url = "/repositories/#{JSONModel::repository}/resource_descriptions/#{params[:id]}.xml"

    download_bhl_export(url, metadata_url,
                    :include_unpublished => (params[:include_unpublished] ? params[:include_unpublished] : false),
                    :print_pdf => (params[:print_pdf] ? params[:print_pdf] : false),
                    :include_daos => (params[:include_daos] ? params[:include_daos] : false),
                    :numbered_cs => (params[:numbered_cs] ? params[:numbered_cs] : false))
  end


  private

  def download_bhl_export(request_uri, metadata_uri, params = {})

    meta = JSONModel::HTTP::get_json("#{metadata_uri}/metadata")

    respond_to do |format|
      format.html {
        self.response.headers["Content-Type"] ||= meta['mimetype']
        self.response.headers["Content-Disposition"] = "attachment; filename=#{meta['filename']}"
        self.response.headers['Last-Modified'] = Time.now.ctime.to_s

        self.response_body = Enumerator.new do |y|
          xml_response(request_uri, params) do |chunk, percent|
            y << chunk if !chunk.blank?
          end
        end
      }
    end
  end

end