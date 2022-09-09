require 'pry'

module DataScript
  class Filter
    def self.filter!(bundles)
      organization_bundle = bundles.find {|b| b.entry.first.resource.resourceType == 'Organization'}
      practitioner_bundle = bundles.find {|b| b.entry.first.resource.resourceType == 'Practitioner'}
      patient_bundles = bundles.select {|b| b.entry.first.resource.resourceType == 'Patient'}

      organizations_to_keep = []
      locations_to_keep = []
      practitioners_to_keep = []

      patient_bundles.each do |bundle|
        print "\n"
        tik = Time.now.to_i
        initial_length = bundle.entry.length
        profile_coverage = []
        encounters_to_keep = []
        resources_to_keep = []

        bundle.entry.reverse.each do |entry|
          next unless ['AllergyIntolerance','Device','Encounter','Goal','RelatedPerson'].include?(entry.resource.resourceType)
          # start by looking at Encounters, most but not all resources reference the Encounter...
          if entry.resource.resourceType == 'Encounter'
            print '.'
            encounter_resources = get_resources_associated_with_encounter(bundle, entry.fullUrl)
            encounter_resources_profiles = encounter_resources.map {|resource| resource&.meta&.profile&.first}.compact
            if encounter_resources_profiles.any? {|p| !profile_coverage.include?(p) }
              profile_coverage.append(encounter_resources_profiles).flatten!
              profile_coverage.uniq!
              encounters_to_keep << entry.resource
              resources_to_keep.append(encounter_resources).flatten!
              organizations_to_keep << entry.resource.serviceProvider
              locations_to_keep << entry.resource.location&.first&.location
              practitioners_to_keep << entry.resource.participant&.first&.individual
            end
          elsif entry.resource.resourceType == 'AllergyIntolerance' # allergyintolerance is special because it does not reference an encounter
            print 'a'
            resource_profile = entry.resource&.meta&.profile&.first
            if resource_profile == 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-allergyintolerance'
              resources_to_keep << entry.resource
              profile_coverage.append(resource_profile).flatten!
              profile_coverage.uniq!
            end
          elsif entry.resource.resourceType == 'Device' # device is special because it does not reference an encounter
            print 'd'
            resource_profile = entry.resource&.meta&.profile&.first
            if resource_profile == 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-implantable-device'
              resources_to_keep << entry.resource
              profile_coverage.append(resource_profile).flatten!
              profile_coverage.uniq!
            end
          elsif entry.resource.resourceType == 'Goal' # goal is special because it does not reference an encounter
            print 'g'
            resource_profile = entry.resource&.meta&.profile&.first
            if resource_profile == 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal'
              resources_to_keep << entry.resource
              profile_coverage.append(resource_profile).flatten!
              profile_coverage.uniq!
            end
          elsif entry.resource.resourceType == 'RelatedPerson' # relatedperson is special because it does not reference anything
            print 'r'
            resource_profile = entry.resource&.meta&.profile&.first
            if resource_profile == 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-relatedperson'
              resources_to_keep << entry.resource
              profile_coverage.append(resource_profile).flatten!
              profile_coverage.uniq!
            end
          end
        end

        # get dangling encounters, e.g., medication X (prescribed in encounter A) with reason condition Y (diagnosed in encounter B)
        resources_to_keep.each do |resource|
          if resource.respond_to?(:encounter)
            encounter_urn = resource.encounter&.reference
            if encounter_urn
              encounter = encounters_to_keep.find{|e| e.id == encounter_urn[9..-1]}
              if encounter.nil?
                print 'e'
                entry = bundle.entry.find {|e| e.fullUrl == encounter_urn }
                encounters_to_keep << entry.resource
              end
            end
          end
        end

        print "\n"

        bundle.entry.keep_if do |entry|
          ['Patient','Provenance'].include?(entry.resource.resourceType) ||
          encounters_to_keep.include?(entry.resource) ||
          resources_to_keep.include?(entry.resource)
        end

        provenance = bundle.entry.find {|e| e.resource.resourceType == 'Provenance' }.resource
        uuids = bundle.entry.map {|e| e.fullUrl}
        provenance.target.keep_if {|reference| uuids.include?(reference.reference) }
        final_length = bundle.entry.length
        tok = Time.now.to_i
        puts "  - Filtered #{initial_length} resources down to #{final_length} (#{DataScript::TimeUtilities.pretty(tok - tik)})."
      end

      patient_bundles.each do |bundle|
        bundle.entry.each do |entry|
          if ['DiagnosticReport'].include?(entry.resource.resourceType)
            entry.resource.performer.each do |performer|
              performer = FHIR::Reference.new(performer) if performer.is_a?(Hash)
              if performer.reference.start_with?('Practitioner')
                practitioners_to_keep << performer
              elsif performer.reference.start_with?('Organization')
                organizations_to_keep << performer
              end
            end
          end
        end
      end

      # array of references into uuids
      organizations_to_keep.map! {|x| x.reference.split('|').last}
      organizations_to_keep.uniq!

      # array of references into uuids
      locations_to_keep.map! {|x| x.reference.split('|').last}
      locations_to_keep.uniq!

      initial_length = organization_bundle.entry.length
      organization_bundle.entry.keep_if do |entry|
        organizations_to_keep.include?(entry.resource.id) ||
        locations_to_keep.include?(entry.resource.id)
      end
      final_length = organization_bundle.entry.length
      puts "  - Filtered #{initial_length} Organization and Location resources down to #{final_length}."

      # array of references into NPIs
      practitioners_to_keep.map! {|x| x.reference.split('|').last}
      practitioners_to_keep.uniq!

      initial_length = practitioner_bundle.entry.length
      practitioner_bundle.entry.keep_if do |entry|
        practitioners_to_keep.include?(entry.resource&.identifier&.first&.value) ||
        (entry.resource.respond_to?(:practitioner) && practitioners_to_keep.include?(entry.resource&.practitioner&.identifier&.value))
      end
      final_length = practitioner_bundle.entry.length
      puts "  - Filtered #{initial_length} Practitioner and PractitionerRole resources down to #{final_length}."
    end

    def self.get_resources_associated_with_encounter(bundle, encounter_urn)
      resources = []
      refd_medications = []
      refd_conditions = []
      refd_related_person = []

      bundle.entry.each do |entry|
        if entry.resource.respond_to?(:encounter) && entry.resource.encounter&.reference == encounter_urn
          resources << entry.resource
          refd_medications << entry.resource.medicationReference&.reference if entry.resource.respond_to?(:medicationReference)
          if entry.resource.respond_to?(:reasonReference)
            refd_conditions << entry.resource.reasonReference&.first&.reference
            # only keep the first reason...
            entry.resource.reasonReference = [ entry.resource.reasonReference.first ]
          end
          refd_related_person << entry.resource&.participant&.find {|x| x&.role&.first&.text = 'Caregiver (person)'}&.member&.reference if entry.resource.resourceType == 'CareTeam'
        elsif entry.resource.resourceType == 'DocumentReference' && entry.resource.context.encounter.first.reference == encounter_urn
          resources << entry.resource
        end
      end

      refd_medications.uniq!
      refd_conditions.uniq!
      refd_related_person.uniq!

      refd_medications.each do |fullUrl|
        resources << bundle.entry.find {|e| e.fullUrl == fullUrl}&.resource
      end

      refd_conditions.each do |fullUrl|
        resources << bundle.entry.find {|e| e.fullUrl == fullUrl}&.resource
      end

      refd_related_person.each do |fullUrl|
        resources << bundle.entry.find {|e| e.fullUrl == fullUrl}&.resource
      end

      resources.uniq!
      resources.compact!
      resources
    end

    def self.create_group(bundles)
      group = FHIR::Group.new
      group.id = SecureRandom.uuid
      group.identifier = [ FHIR::Identifier.new ]
      group.identifier.first.system = 'urn:ietf:rfc:3986'
      group.identifier.first.value = "urn:uuid:#{group.id}"
      group.active = true
      group.type = 'person'
      group.actual = true
      group.name = 'Synthea US Core Patients'
      patient_bundles = bundles.select {|b| b.entry.first.resource.resourceType == 'Patient'}
      group.quantity = patient_bundles.length
      group.member = []
      patient_bundles.each do |bundle|
        group_member = FHIR::Group::Member.new
        group_member.entity = FHIR::Reference.new
        group_member.entity.reference = "Patient?identifier=https://github.com/synthetichealth/synthea|#{bundle.entry.first.resource.id}"
        # group_member.entity.reference = bundle.entry.first.fullUrl
        # group_member.entity.identifier = FHIR::Identifier.new
        # group_member.entity.identifier.system = 'https://github.com/synthetichealth/synthea'
        # group_member.entity.identifier.value = bundle.entry.first.resource.id
        group.member << group_member
      end
      group
    end
  end
end
