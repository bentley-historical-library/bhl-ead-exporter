# encoding: utf-8
require 'nokogiri'
require 'securerandom'

require_relative 'lib/descgrp_types'
require_relative 'lib/singularize_extents'
require_relative 'lib/university_restrictions'

class BHLEADSerializer < ASpaceExport::Serializer
  serializer_for :bhl_ead

  # Allow plugins to hook in to record processing by providing their own
  # serialization step (a class with a 'call' method accepting the arguments
  # defined in `run_serialize_step`.
  def self.add_serialize_step(serialize_step)
    @extra_serialize_steps ||= []
    @extra_serialize_steps << serialize_step
  end

  def self.run_serialize_step(data, xml, fragments, context)
    Array(@extra_serialize_steps).each do |step|
      step.new.call(data, xml, fragments, context)
    end
  end


  def prefix_id(id)
    if id.nil? or id.empty? or id == 'null'   
      ""
    elsif id =~ /^#{@id_prefix}/ 
      id
    else 
      "#{@id_prefix}#{id}"
    end 
  end
 
  def xml_errors(content)
    # there are message we want to ignore. annoying that java xml lib doesn't
    # use codes like libxml does...
    ignore = [ /Namespace prefix .* is not defined/, /The prefix .* is not bound/  ] 
    ignore = Regexp.union(ignore) 
    # the "wrap" is just to ensure that there is a psuedo root element to eliminate a "false" error
    Nokogiri::XML("<wrap>#{content}</wrap>").errors.reject { |e| e.message =~ ignore  }
  end 


  def handle_linebreaks(content)
    # 4archon... 
    content.gsub!("\n\t", "\n\n")  
    # if there's already p tags, just leave as is
    return content if ( content.strip =~ /^<p(\s|\/|>)/ or content.strip.length < 1 )
    original_content = content
    blocks = content.split("\n\n").select { |b| !b.strip.empty? }
    if blocks.length > 1
      content = blocks.inject("") { |c,n| c << "<p>#{n.chomp}</p>"  }
    else
      content = "<p>#{content.strip}</p>"
    end

    # first lets see if there are any &
    # note if there's a &somewordwithnospace , the error is EntityRef and wont
    # be fixed here...
    if xml_errors(content).any? { |e| e.message.include?("The entity name must immediately follow the '&' in the entity reference.") }
      content.gsub!("& ", "&amp; ")
    end

    # in some cases adding p tags can create invalid markup with mixed content
    # just return the original content if there's still problems
    xml_errors(content).any? ? original_content : content
  end

  def strip_p(content)
    content.gsub("<p>", "").gsub("</p>", "").gsub("<p/>", '')
  end

  def remove_smart_quotes(content)
    content = content.gsub(/\xE2\x80\x9C/, '"').gsub(/\xE2\x80\x9D/, '"').gsub(/\xE2\x80\x98/, "\'").gsub(/\xE2\x80\x99/, "\'")
  end

  def sanitize_mixed_content(content, context, fragments, allow_p = false  )
#    return "" if content.nil? 

    # remove smart quotes from text
    content = remove_smart_quotes(content)

    # br's should be self closing 
    content = content.gsub("<br>", "<br/>").gsub("</br>", '')
    # lets break the text, if it has linebreaks but no p tags.  
    
    # MODIFICATION: Added a sort of hacky way to preserve <p> tags in lists
    # allow_p = true adds ps where they shouldn't be, and allow_p = false removes ps where it shouldn't
    # allow_p = "neither" leaves everything just the way it is. Currently only used in list/items
    if allow_p == "neither"
        content = content
    elsif allow_p
      content = handle_linebreaks(content) 
    else
      content = strip_p(content)
    end
    
    begin 
      if ASpaceExport::Utils.has_html?(content)
         context.text( fragments << content )
      else
        context.text content.gsub("&amp;", "&") #thanks, Nokogiri
      end
    rescue
      context.cdata content
    end
  end
  
  def stream(data)
    @stream_handler = ASpaceExport::StreamHandler.new
    @fragments = ASpaceExport::RawXMLHandler.new
    @include_unpublished = data.include_unpublished?
    @include_daos = data.include_daos?
    @use_numbered_c_tags = data.use_numbered_c_tags?
    @restriction_types = data.restriction_types
    @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

    doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
      begin 
      # MODIFICATION: Added doctype and removed namespaces
      xml.doc.create_internal_subset('ead',"+//ISBN 1-931666-00-8//DTD ead.dtd (Encoded Archival Description (EAD) Version 2002)//EN","ead.dtd")
      
      ead_attributes = {}

      if data.publish === false
        ead_attributes['audience'] = 'internal'
      end

      xml.ead( ead_attributes ) {

        xml.text (
          @stream_handler.buffer { |xml, new_fragments|
            serialize_eadheader(data, xml, new_fragments)
           # MODIFICATION: Serialize frontmatter for DLXS
            serialize_frontmatter(data, xml, new_fragments)
          })

        atts = {:level => data.level, :otherlevel => data.other_level}
        atts.reject! {|k, v| v.nil?}        

        xml.archdesc(atts) {
            


          xml.did {
          
            # MODIFICATION: Don't export the content of the Language drop down as a langmaterial element, as this ends of creating two langmaterials
            # The one that we really want exported is from the "Language of Materials" text note
            #if (val = data.language)
              #xml.langmaterial {
                #xml.language(:langcode => val) {
                  #xml.text I18n.t("enumerations.language_iso639_2.#{val}", :default => val)
                #}
              #}
            #end
            #  MODIFICATION: Added bhladd extptr to repository
            if (val = data.repo.name)
              xml.repository {
                xml.corpname { sanitize_mixed_content(val, xml, @fragments) }
                xml.extptr({
                            "href"=>"bhladd",
                            "show"=>"embed",
                            "actuate"=>"onload"
                            })
              }
            end

            if (val = data.title)
              xml.unittitle  {   sanitize_mixed_content(val, xml, @fragments) } 
            end

            serialize_origination(data, xml, @fragments)

            # MODIFICATION: Add a type="call number" attribute to collection level unitids
            xml.unitid(:type => 'call number') { xml.text (0..3).map{|i| data.send("id_#{i}")}.compact.join('.')}

            serialize_extents(data, xml, @fragments, level="resource")
            serialize_dates(data, xml, @fragments)
             # MODIFICATION: Set serialize_x_notes levels to resource so that extptrs are added to accessrestrict and processinfo
            serialize_did_notes(data, xml, @fragments, level="resource")

            # MODIFICATION: Don't serialize resource level containers or digital objects
            #data.instances_with_sub_containers.each do |instance|
              #serialize_container(instance, xml, @fragments)
            #end

            EADSerializer.run_serialize_step(data, xml, @fragments, :did)

          }# </did>

          #data.digital_objects.each do |dob|
            #serialize_digital_object(dob, xml, @fragments)
          #end
            
          # MODIFICATION: Serialize <descgrp type="admin">

          uarp_classification = false

          unless data.user_defined.nil?
            [1, 2, 3].each do |i|
              if data.user_defined.has_key?("enum_#{i}") and not data.user_defined["enum_#{i}"].nil?
                classification = data.user_defined["enum_#{i}"]
                if classification == "UA"
                  uarp_classification = true
                end
              end
            end
          end

          xml.descgrp({'type'=>'admin'}) {
            serialize_descgrp_admin_notes(data, xml, @fragments,level="resource", uarp_classification)
          }


          serialize_nondid_notes(data, xml, @fragments, level="resource")

          serialize_bibliographies(data, xml, @fragments)


          serialize_controlaccess(data, xml, @fragments)

          EADSerializer.run_serialize_step(data, xml, @fragments, :archdesc)

          xml.dsc({'type'=>'combined'}) {

            data.children_indexes.each do |i|
              xml.text(
                       @stream_handler.buffer {|xml, new_fragments|
                         serialize_child(data.get_child(i), xml, new_fragments)
                       }
                       )
            end
          }

          # MODIFICATION: Serialize <descgrp type="add">

          descgrp_add = false

          data.notes.each do |note|
            if DescgrpTypes.descgrp_add.include?(note['type'])
              descgrp_add = true
            end
          end

          if descgrp_add or data.indexes.length > 0
            xml.descgrp({'type'=>'add'}) {
              serialize_descgrp_add_notes(data, xml, @fragments,level="resource")
              serialize_indexes(data, xml, @fragments)
            }
          end
        }
      }
    
    rescue => e
      xml.text  "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF YOUR RESOURCE. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end
 
    
    
    end
    # MODIFICATION: Commenting out namespace
    #doc.doc.root.add_namespace nil, 'urn:isbn:1-931666-22-9'

    Enumerator.new do |y|
      @stream_handler.stream_out(doc, @fragments, y)
    end
  
    
  end
  
  # this extracts <head> content and returns it. optionally, you can provide a
  # backup text node that will be returned if there is no <head> nodes in the
  # content
  def extract_head_text(content, backup = "")
    content ||= ""  
    match = content.strip.match(/<head( [^<>]+)?>(.+?)<\/head>/)
    if match.nil? # content has no head so we return it as it
      return [content, backup ]
    else
      [ content.gsub(match.to_a.first, ''), match.to_a.last]
    end
  end

  def serialize_child(data, xml, fragments, c_depth = 1, inheritable_restriction = false)
    begin 
    return if data["publish"] === false && !@include_unpublished
    return if data["suppressed"] === true

    tag_name = @use_numbered_c_tags ? :"c#{c_depth.to_s.rjust(2, '0')}" : :c

    atts = {:level => data.level, :otherlevel => data.other_level, :id => prefix_id(data.ref_id)}

    if data.publish === false
      atts[:audience] = 'internal'
    end

    atts.reject! {|k, v| v.nil?}
    xml.send(tag_name, atts) {

      xml.did {
        if (val = data.title)
          xml.unittitle {  sanitize_mixed_content( val,xml, fragments) } 
        end

        if !data.component_id.nil? && !data.component_id.empty?
          xml.unitid "[" + data.component_id + "]"
        end

        serialize_origination(data, xml, fragments)
        serialize_extents(data, xml, fragments, level="child")
        serialize_dates(data, xml, fragments)
        # MODIFICATION: Set serialize_x_notes level to "child" so that extptrs are not added to accessrestrict or processinfo
        serialize_did_notes(data, xml, fragments, level="child")

        EADSerializer.run_serialize_step(data, xml, fragments, :did)

        # TODO: Clean this up more; there's probably a better way to do this.
        # For whatever reason, the old ead_containers method was not working
        # on archival_objects (see migrations/models/ead.rb).

        has_physical_instance = false
        has_digital_instance = false

        if data.instances_with_sub_containers.length > 0
          has_physical_instance = true
          data.instances_with_sub_containers.each do |instance|
            serialize_container(instance, xml, @fragments)
          end
        end

        if @include_daos && data.instances_with_digital_objects.length > 0
          has_digital_instance = true
          data.instances_with_digital_objects.each do |instance|
            serialize_digital_object(instance["digital_object"]["_resolved"], xml, fragments)
          end
        end

        # MODIFICATION: Export <physloc>Online</physloc> when there is only a digital instance
        if has_digital_instance and not has_physical_instance
          xml.physloc "Online"
        end

      }

      serialize_nondid_notes(data, xml, fragments, level="child")

      accessrestricts = data.notes.select{|n| n["type"] == "accessrestrict"}
      if accessrestricts.length > 0
        inheritable_restriction = accessrestricts[0]
      elsif inheritable_restriction
        serialize_note_content(inheritable_restriction, xml, fragments, level="child")
      end

      serialize_bibliographies(data, xml, fragments)

      serialize_indexes(data, xml, fragments)

      #serialize_controlaccess(data, xml, fragments)

      EADSerializer.run_serialize_step(data, xml, fragments, :archdesc)

      data.children_indexes.each do |i|
        xml.text(
                 @stream_handler.buffer {|xml, new_fragments|
                   serialize_child(data.get_child(i), xml, new_fragments, c_depth + 1, inheritable_restriction=inheritable_restriction)
                 }
                 )
      end
    }
    rescue => e
      xml.text "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF ARCHIVAL OBJECTS. THE FOLLOWING INFORMATION MAY HELP:\n

                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end
  end


  def serialize_origination(data, xml, fragments)
    unless data.creators_and_sources.nil?
      data.creators_and_sources.each do |link|
        agent = link['_resolved']
        role = link['role']
        relator = link['relator']
        sort_name = agent['display_name']['sort_name']
        rules = agent['display_name']['rules']
        source = agent['display_name']['source']
        authfilenumber = agent['display_name']['authority_id']
        node_name = case agent['agent_type']
                    when 'agent_person'; 'persname'
                    when 'agent_family'; 'famname'
                    when 'agent_corporate_entity'; 'corpname'
                    end
        xml.origination(:label => role) {
         atts = {:role => relator, :source => source, :rules => rules, :authfilenumber => authfilenumber}
         atts.reject! {|k, v| v.nil?}

          xml.send(node_name, atts) {
            sanitize_mixed_content(sort_name, xml, fragments ) 
          }
        }
      end
    end
  end

  # MODIFICATION: Add accnote extptr to controlaccess
  # Modification: ensure that subjects and agents end with punctuation
  def serialize_controlaccess(data, xml, fragments)
    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents.length) > 0
      xml.controlaccess {
        xml.p { 
            xml.extptr({
                        "href"=>"accnote", 
                        "show"=>"embed", 
                        "actuate"=>"onload"
                        })
                }
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

  def serialize_subnotes(subnotes, xml, fragments, include_p = true, note_type, level)
    subnotes.each do |sn|
      next if sn["publish"] === false && !@include_unpublished

      audatt = sn["publish"] === false ? {:audience => 'internal'} : {}

      title = sn['title']

      case sn['jsonmodel_type']
      # MODIFICIATION: Wrap odd and abstract text in parens if there is only one paragraph
      when 'note_text'
        content = sn['content']
        if note_type == 'odd' && level == 'child' && !(content.strip =~ /^[\[\(]/)
          blocks = content.split("\n\n")
          if blocks.length == 1 && subnotes.length == 1
            content = "(#{content.strip})"
          end
        end
        if note_type == 'accessrestrict' && level == 'child' && !(content.strip =~ /^[\[\(]/)
          blocks = content.split("\n\n")
          if blocks.length == 1 && subnotes.length == 1
            content = "[#{content.strip}]"
          end
        end
        sanitize_mixed_content(content, xml, fragments, include_p )
      when 'note_chronology'
        xml.chronlist(audatt) {
          xml.head { sanitize_mixed_content(title, xml, fragments) } if title

          sn['items'].each do |item|
            xml.chronitem {
              if (val = item['event_date'])
                xml.date {   sanitize_mixed_content( val, xml, fragments) } 
              end
              if item['events'] && !item['events'].empty?
                xml.eventgrp {
                  item['events'].each do |event|
                    xml.event {   sanitize_mixed_content(event,xml, fragments) }  
                  end
                }
              end
            }
          end
        }
      when 'note_orderedlist'
        atts = {:type => 'ordered', :numeration => sn['enumeration']}.reject{|k,v| v.nil? || v.empty? || v == "null" }.merge(audatt)
        xml.list(atts) {
          xml.head { sanitize_mixed_content(title, xml, fragments) }  if title

          # MODIFCATION: Set allow_p to "neither" for list/items so that ps are not added or removed

          sn['items'].each do |item|
            xml.item { sanitize_mixed_content(item,xml, fragments, allow_p = "neither")} 
          end
        }
      when 'note_definedlist'
        xml.list({:type => 'deflist'}.merge(audatt)) {
          xml.head { sanitize_mixed_content(title,xml, fragments) }  if title

          sn['items'].each do |item|
            xml.defitem {
              xml.label { sanitize_mixed_content(item['label'], xml, fragments) } if item['label']
              xml.item { sanitize_mixed_content(item['value'],xml, fragments )} if item['value']
            } 
          end
        }
      end
    end
  end

  def serialize_container(inst, xml, fragments)
    atts = {}

    sub = inst['sub_container']
    top = sub['top_container']['_resolved']

    #atts[:id] = top_id
    #last_id = atts[:id]

    top_type = top['type']

    if top_type.include?("Roll")
      top_top = "reel"
    elsif top_type.include?("Con.") or top_type.include?("No.")
      top_type = "othertype"
    else
      top_type = top_type.downcase
    end

    atts[:type] = top_type
    text = top['indicator']

    atts[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}", :default => inst['instance_type'])
    #atts[:label] << " [#{top['barcode']}]" if top['barcode']

    #if (cp = top['container_profile'])
      #atts[:altrender] = cp['_resolved']['url'] || cp['_resolved']['name']
    #end

    xml.container(atts) {
      sanitize_mixed_content(text, xml, fragments)
    }

    (2..3).each do |n|
      atts = {}

      next unless sub["type_#{n}"]

      #atts[:id] = prefix_id(SecureRandom.hex)
      #atts[:parent] = last_id
      #last_id = atts[:id]

      sub_type = sub["type_#{n}"]
      if sub_type.include?("Roll")
        sub_label = sub_type
        sub_type = "reel"
      elsif sub_type.include?("Con.") or sub_type.include?("No.")
        sub_label = sub_type
        sub_type = "othertype"
      else
        sub_label = sub_type.capitalize
        sub_type = sub_type.downcase
      end

      atts[:type] = sub_type
      atts[:label] = sub_label
      text = sub["indicator_#{n}"]

      xml.container(atts) {
        sanitize_mixed_content(text, xml, fragments)
      }
    end
  end

  def serialize_digital_object(digital_object, xml, fragments)
    return if digital_object["publish"] === false && !@include_unpublished
    return if digital_object["suppressed"] === true

    file_versions = digital_object['file_versions']
    digital_object_notes = digital_object['notes']
    title = digital_object['title']
    date = digital_object['dates'][0] || {}
    
    atts = digital_object["publish"] === false ? {:audience => 'internal'} : {}

    content = ""
    content << title if title
    content << ": " if date['expression'] || date['begin']
    if date['expression']
      content << date['expression']
    elsif date['begin']
      content << date['begin']
      if date['end'] != date['begin']
        content << "-#{date['end']}"
      end
    end
    atts['title'] = digital_object['title'] if digital_object['title']
        
    #MODIFICATION: Insert original note into <daodesc> instead of the default title
    daodesc_content = "[access item]"
    
    digital_object_notes.each do |note|
        if note['type'] == 'note'
            daodesc_content = "[#{note['content'][0]}]"
        end
    end    
    
    if file_versions.empty?
      atts['href'] = digital_object['digital_object_id']
      atts['actuate'] = 'onrequest'
      atts['show'] = 'new'
      xml.dao(atts) {
        xml.daodesc { sanitize_mixed_content(daodesc_content, xml, fragments, true) } if content
      }
    else
      file_versions.each do |file_version|
        atts['href'] = file_version['file_uri'] || digital_object['digital_object_id']
        # MODIFICATION: downcase xlink_actuate_attribute
        atts['actuate'] = file_version['xlink_actuate_attribute'] ? file_version['xlink_actuate_attribute'].downcase : 'onrequest'
        atts['show'] = file_version['xlink_show_attribute'] || 'new'
        xml.dao(atts) {
          xml.daodesc { sanitize_mixed_content(daodesc_content, xml, fragments, true) } if content
        }
      end
    end
    
  end

  # MODIFCATION: Assemble a single extent statement in one physdesc
  def serialize_extents(obj, xml, fragments, level)
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
        extent_number_and_type = "#{e['number']} #{extent_type}"
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
      if level == "resource"
        extent_statements.each do |content|
            xml.physdesc {
                xml.extent {
                  sanitize_mixed_content(content, xml, fragments)  
            }
          }
        end
      elsif level == "child"
       xml.physdesc {
                xml.extent {
                  sanitize_mixed_content(extent_statements.join(', '), xml, fragments)  
            }
          }
      end
    end
  end


  def serialize_dates(obj, xml, fragments)
    obj.archdesc_dates.each do |node_data|
      next if node_data["publish"] === false && !@include_unpublished
      audatt = node_data["publish"] === false ? {:audience => 'internal'} : {}
      xml.unitdate(node_data[:atts].merge(audatt)){
        sanitize_mixed_content( node_data[:content],xml, fragments ) 
      }
    end
  end

  def serialize_did_notes(data, xml, fragments, level)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next unless data.did_note_types.include?(note['type'])

      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)

      if note['type'] == 'abstract' && level == 'child'
        content = "(#{content.strip})"
      end

      att = { :id => prefix_id(note['persistent_id']) }.reject {|k,v| v.nil? || v.empty? || v == "null" } 
      att ||= {}

      case note['type']
      when 'dimensions', 'physfacet'
        xml.physdesc(audatt) {
          xml.send(note['type'], att) {
            sanitize_mixed_content( content, xml, fragments, ASpaceExport::Utils.include_p?(note['type'])  ) 
          }
        }
      else
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments,ASpaceExport::Utils.include_p?(note['type']))
        }
      end
    end
  end
    
  # MODIFICATION: Add extptr to processinfo and accessrestrict when appropriate
  def serialize_note_content(note, xml, fragments, level, uarp_classification=false)
    return if note["publish"] === false && !@include_unpublished
    audatt = note["publish"] === false ? {:audience => 'internal'} : {}
    content = note["content"] 

    atts = audatt
    
    # MODIFICATION: Only export a head tag if there is a note label to avoid exporting a <head> tag for every single note
    head_text = note['label'] if note['label'] #? note['label'] : I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
    content, head_text = extract_head_text(content, head_text) 
    # MODIFICATION: Add uarpacc extptr for resource level accessrestricts
    if note['type'] == 'accessrestrict'    
        if level == 'resource'
            xml.accessrestrict(atts) {
                if head_text
                xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content ) 
                end
                sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
                if note['subnotes']
                    serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']), note['type'], level)
                end

                if @restriction_types.count > 0
                  xml.restriction_types { xml.text(@restriction_types) }
                  university_restriction_types = UniversityRestrictions.university_restriction_types
                  present_types = []
                  @restriction_types.each do |restriction_type|
                    if university_restriction_types.include?(restriction_type)
                      present_types << restriction_type
                    end
                  end

                  if present_types.count > 0
                    xml.p {
                      xml.blockquote {
                        xml.p { xml.emph("render" => "bold") { xml.text(UniversityRestrictions.header_text) } }
                        xml.p { xml.text(UniversityRestrictions.boilerplate_start) }
                        xml.p { xml.text("Categories of Restricted Records")
                          xml.list("type" => "simple") {
                            if present_types.include?("PR")
                              xml.item { sanitize_mixed_content(UniversityRestrictions.pr_restrictions, xml, fragments)}
                            end
                            if present_types.include?("SR")
                              xml.item { sanitize_mixed_content(UniversityRestrictions.sr_restrictions, xml, fragments)}
                            end
                            if present_types.include?("CR")
                              xml.item { sanitize_mixed_content(UniversityRestrictions.cr_restrictions, xml, fragments)}
                            end
                            if present_types.include?("ER")
                              xml.item { sanitize_mixed_content(UniversityRestrictions.er_restrictions, xml, fragments)}
                            end
                          }
                        }
                        xml.p { xml.text(UniversityRestrictions.boilerplate_contents_list)}
                        xml.p { xml.text(UniversityRestrictions.boilerplate_foia)}
                      }
                    }
                  end
                end
              }
        elsif level == 'child'
            xml.accessrestrict(atts) {
                if head_text
                xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content ) 
                end
                sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
                if note['subnotes']
                    serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']), note['type'], level)
                end
            }
        end
    # MODIFICATION: Add digitalproc extptrs to processinfo
    elsif note['type'] == 'processinfo'
        xml.processinfo(atts) {
            if head_text
            xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content ) 
            end
            sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
            if note['subnotes']
                serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']), note['type'], level)
            end

            digitalproc_exists = false
            note['subnotes'].each do |sn|
              if sn['content'] && sn['content'].include?('digitalproc')
                digitalproc_exists = true
              end
            end

            if not digitalproc_exists
              xml.p {
                  xml.extptr( {
                              "href"=>"digitalproc",
                              "show"=>"embed",
                              "actuate"=>"onload"
                              } )
                      }
            end
            }
    elsif note['type'] == "arrangement" && level == "child"
      xml.odd(atts) {
          if head_text
          xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content ) 
          end
          sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
          # MODIFICIATON: Send along note['type'] to insert parens inside odds
          if note['subnotes']
            serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']), note['type'], level)
          end
        }
    else
        xml.send(note['type'], atts) {
          if head_text
          xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content ) 
          end
          sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
          # MODIFICIATON: Send along note['type'] to insert parens inside odds
          if note['subnotes']
            serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']), note['type'], level)
          end
        }
    end
  end

  # MODIFICATION: Put some notes in <descgrp type="admin">
  def serialize_descgrp_admin_notes(data, xml, fragments, level, uarp_classification=false)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next if note["internal"]
      next if note['type'].nil?
      next unless DescgrpTypes.descgrp_admin.include?(note['type'])
      serialize_note_content(note,xml,fragments,level, uarp_classification)
    end
  end

  # MODIFICATION: Put some other notes in <descgrp type="add">
  def serialize_descgrp_add_notes(data, xml, fragments, level)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next if note["internal"]
      next if note['type'].nil?
      next unless DescgrpTypes.descgrp_add.include?(note['type'])
      serialize_note_content(note,xml,fragments,level)
    end
  end

  # MODIFICATION: Pass along the note's level to send to serialize_note_content to differentiate resource and component level accessrestricts
  # MODIFICATION: Only serialize notes that do not belong in <descgrp type="admin"> or <descgrp type="add">
  def serialize_nondid_notes(data, xml, fragments, level)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next if note['internal']
      next if note['type'].nil?
      next if DescgrpTypes.descgrp_admin.include?(note['type']) && level == "resource"
      next if DescgrpTypes.descgrp_add.include?(note['type']) && level == "resource"
      next unless data.archdesc_note_types.include?(note['type'])
      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      if note['type'] == 'legalstatus'
        xml.accessrestrict(audatt) {
          serialize_note_content(note, xml, fragments, level) 
        }
      else
        serialize_note_content(note, xml, fragments, level)
      end
    end
  end


  def serialize_bibliographies(data, xml, fragments)
    data.bibliographies.each do |note|
      next if note["publish"] === false && !@include_unpublished
      content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)
      note_type = note["type"] ? note["type"] : "bibliography" 
      head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note_type}", :default => note_type )
      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      
      atts = {:id => prefix_id(note['persistent_id']) }.reject{|k,v| v.nil? || v.empty? || v == "null" }.merge(audatt)

      xml.bibliography(atts) {
        xml.head { sanitize_mixed_content(head_text, xml, fragments) } 
        sanitize_mixed_content( content, xml, fragments, true) 
        note['items'].each do |item|
          xml.bibref { sanitize_mixed_content( item, xml, fragments) }  unless item.empty?
        end
      }
    end
  end


  def serialize_indexes(data, xml, fragments)
    data.indexes.each do |note|
      # MODIFICATION: Export indexes even if they are unpublished (due to some legacy import issues)
      #next if note["publish"] === false && !@include_unpublished
      #audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)
      head_text = nil
      if note['label']
        head_text = note['label']
      #elsif note['type']
        #head_text = I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
      end
      atts = {:id => prefix_id(note["persistent_id"]) }.reject{|k,v| v.nil? || v.empty? || v == "null" } #.merge(audatt)

      content, head_text = extract_head_text(content, head_text) 
      xml.index(atts) {
        xml.head { sanitize_mixed_content(head_text,xml,fragments ) } unless head_text.nil?
        sanitize_mixed_content(content, xml, fragments, true)
        note['items'].each do |item|
          next unless (node_name = data.index_item_type_map[item['type']])
          xml.indexentry {
            atts = item['reference'] ? {:target => prefix_id( item['reference']) } : {}
            if (val = item['value'])
              xml.send(node_name) {  sanitize_mixed_content(val, xml, fragments )} 
            end
            if (val = item['reference_text'])
              xml.ref(atts) {
                # MODIFICATION: Export indexentry refs in list/item tags for DLXS
                xml.list({:type=>'simple'}) {
                  xml.item {
                    sanitize_mixed_content(val, xml, fragments)
                  }
                }
              }
            end
          }
        end
      }
    end
  end

  # MODIFICATION: Serialize frontmatter for DLXS
  # Currently not serializing classification (i.e., "Michigan Historical Collections", "UARP", etc.)

  def serialize_frontmatter(data, xml, fragments)
    xml.frontmatter {
      xml.titlepage {
        #classification_ref = nil
        #classification_title = nil

        #data.classifications.each do |classification|
          #classification_ref = classification['ref']
        #end

        #if classification_ref
          #classification_title = resolve_classification(classification_ref)
        #end

        publisher = ""
        #publisher += "#{classification_title} <lb/>" if classification_title
        publisher += data.repo.name + " <lb/>University of Michigan"

        xml.publisher { sanitize_mixed_content(publisher, xml, fragments) }
        xml.titleproper { sanitize_mixed_content(data.finding_aid_title, xml, fragments) }
        xml.author { sanitize_mixed_content(data.finding_aid_author, xml, fragments) }  unless data.finding_aid_author.nil?
        }
     }

  end

  def serialize_eadheader(data, xml, fragments)
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
          # MODIFICATION: Don't export the call number in titleproper
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
              xml.extref ({"href" => data.repo.image_url,
                          "actuate" => "onload",
                          "show" => "embed",
                          "type" => "simple" 
                          })
                          }
          end
          if (data.finding_aid_date)
            xml.p {
                  val = data.finding_aid_date   
                  xml.date {   sanitize_mixed_content( val, xml, fragments) }
                  }
          end
# MODIFICATION: Comment out address
=begin
          unless data.addresslines.empty?
            xml.address {
              data.addresslines.each do |line|
                xml.addressline { sanitize_mixed_content( line, xml, fragments) }  
              end
              if data.repo.url 
                xml.addressline ( "URL: " ) { 
                  xml.extptr ( { 
                          "href" => data.repo.url,
                          "title" => data.repo.url,
                          "show" => "new"
                                # MODIFICATION: Removed 'type' attribute
                          } )
                 }
              end
            }
          end
=end
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
end