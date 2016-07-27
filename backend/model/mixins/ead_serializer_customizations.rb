module EADSerializerCustomizations

  def self.included(base)
    base.class_eval do
      def serialize_extents(data, xml, fragments)
        modified_serialize_extents(data, xml, fragments)
      end
      
      def serialize_controlaccess(data, xml, fragments)
        modified_serialize_controlaccess(data, xml, fragments)
      end
    end
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
