module EADSerializerCustomizations

  def self.included(base)
    base.class_eval do

      def serialize_eadheader(data, xml, fragments)
        modified_serialize_eadheader(data, xml, fragments)
      end

      def serialize_extents(data, xml, fragments)
        modified_serialize_extents(data, xml, fragments)
      end
      
      def serialize_controlaccess(data, xml, fragments)
        modified_serialize_controlaccess(data, xml, fragments)
      end

    end
  end

  def modified_serialize_eadheader(data, xml, fragments)
    eadheader_atts = {:findaidstatus => data.finding_aid_status,
                      :repositoryencoding => "iso15511",
                      :countryencoding => "iso3166-1",
                      :dateencoding => "iso8601",
                      :langencoding => "iso639-2b"}.reject{|k,v| v.nil? || v.empty? || v == "null"}

    xml.eadheader(eadheader_atts) {

      eadid_atts = {:countrycode => data.repo.country,
              :url => data.ead_location,
              :mainagencycode => data.mainagencycode}.reject{|k,v| v.nil? || v.empty? || v == "null" }

      xml.eadid(eadid_atts) {
        xml.text data.ead_id
      }

      xml.filedesc {

        xml.titlestmt {

          titleproper = ""
          titleproper += "#{data.finding_aid_title} " if data.finding_aid_title
          titleproper += "#{data.title}" if ( data.title && titleproper.empty? )
          #titleproper += "<num>#{(0..3).map{|i| data.send("id_#{i}")}.compact.join('.')}</num>"
          xml.titleproper("type" => "filing") { sanitize_mixed_content(data.finding_aid_filing_title, xml, fragments)} unless data.finding_aid_filing_title.nil?
          xml.titleproper {  sanitize_mixed_content(titleproper, xml, fragments) }
          xml.subtitle {  sanitize_mixed_content(data.finding_aid_subtitle, xml, fragments) } unless data.finding_aid_subtitle.nil?
          xml.author { sanitize_mixed_content(data.finding_aid_author, xml, fragments) }  unless data.finding_aid_author.nil?
          xml.sponsor { sanitize_mixed_content( data.finding_aid_sponsor, xml, fragments) } unless data.finding_aid_sponsor.nil?

        }

        unless data.finding_aid_edition_statement.nil?
          xml.editionstmt {
            sanitize_mixed_content(data.finding_aid_edition_statement, xml, fragments, true )
          }
        end

        xml.publicationstmt {
          xml.publisher { sanitize_mixed_content(data.repo.name,xml, fragments) }

          if data.repo.image_url
            xml.p ( { "id" => "logostmt" } ) {
              xml.extref ({"xlink:href" => data.repo.image_url,
                          "xlink:actuate" => "onLoad",
                          "xlink:show" => "embed",
                          "xlink:type" => "simple"
                          })
                          }
          end
          if (data.finding_aid_date)
            xml.p {
                  val = data.finding_aid_date
                  xml.date {   sanitize_mixed_content( val, xml, fragments) }
                  }
          end

          unless data.addresslines.empty?
            xml.address {
              data.addresslines.each do |line|
                xml.addressline { sanitize_mixed_content( line, xml, fragments) }
              end
              if data.repo.url
                xml.addressline ( "URL: " ) {
                  xml.extptr ( {
                          "xlink:href" => data.repo.url,
                          "xlink:title" => data.repo.url,
                          "xlink:type" => "simple",
                          "xlink:show" => "new"
                          } )
                 }
              end
            }
          end
        }

        if (data.finding_aid_series_statement)
          val = data.finding_aid_series_statement
          xml.seriesstmt {
            sanitize_mixed_content(  val, xml, fragments, true )
          }
        end
        if ( data.finding_aid_note )
            val = data.finding_aid_note
            xml.notestmt { xml.note { sanitize_mixed_content(  val, xml, fragments, true )} }
        end

      }

      xml.profiledesc {
        creation = "This finding aid was produced using ArchivesSpace on <date>#{Time.now}</date>."
        xml.creation {  sanitize_mixed_content( creation, xml, fragments) }

        if (val = data.finding_aid_language)
          xml.langusage (fragments << val)
        end

        if (val = data.descrules)
          xml.descrules { sanitize_mixed_content(val, xml, fragments) }
        end
      }

      if data.revision_statements.length > 0
        xml.revisiondesc {
          data.revision_statements.each do |rs|
              if rs['description'] && rs['description'].strip.start_with?('<')
                xml.text (fragments << rs['description'] )
              else
                xml.change {
                  rev_date = rs['date'] ? rs['date'] : ""
                  xml.date (fragments <<  rev_date )
                  xml.item (fragments << rs['description']) if rs['description']
                }
              end
          end
        }
      end
    }
  end

  def modified_serialize_extents(obj, xml, fragments)
    extent_statements = []
    if obj.extents.length
      obj.extents.each do |e|
        next if e["publish"] === false && !@include_unpublished
        audatt = e["publish"] === false ? {:audience => 'internal'} : {}
        extent_statement = ''
        extent_number_float = e['number'].to_f
        extent_type = e['extent_type']
        if extent_number_float == 1.0
          extent_type = SingularizeExtents.singularize_extent(extent_type)
        end
        extent_number_and_type = "#{e['number']} #{I18n.t('enumerations.extent_extent_type.'+extent_type, :default => extent_type)}"
        physical_details = []
        physical_details << e['container_summary'] if e['container_summary']
        physical_details << e['physical_details'] if e['physical_details']
        physical_details << e['dimensions'] if e['dimensions']
        physical_detail = physical_details.join('; ')
        if extent_number_and_type && physical_details.length > 0
          extent_statement += extent_number_and_type + ' (' + physical_detail + ')'
        else
          extent_statement += extent_number_and_type
        end
        extent_statements << extent_statement
      end
    end
    
    if extent_statements.length > 0
       xml.physdesc {
                xml.extent {
                  sanitize_mixed_content(extent_statements.join(', '), xml, fragments)  
            }
          }
      end
  end

  def modified_serialize_controlaccess(data, xml, fragments)
    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents.length) > 0
      xml.controlaccess {
        data.controlaccess_subjects.each do |node_data|
          content = node_data[:content].strip
          if not content =~ /[\.\)\-]$/
            content += "."
          end
          xml.send(node_data[:node_name], node_data[:atts]) {
            sanitize_mixed_content( content, xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) ) 
          }
        end


        data.controlaccess_linked_agents.each do |node_data|
          content = node_data[:content].strip
          if content.include?(" -- ")
            pieces = content.split(" -- ")
            if pieces[0] =~ /\.$/
              pieces[0] = pieces[0].gsub(/\.$/,"")
            end
            content = pieces.join(" -- ")
          end
          if not content =~ /[\.\)\-]$/
            content += "."
          end
          xml.send(node_data[:node_name], node_data[:atts]) {
            sanitize_mixed_content( content, xml, fragments,ASpaceExport::Utils.include_p?(node_data[:node_name]) ) 
          }
        end

      } #</controlaccess>
    end
  end

end
