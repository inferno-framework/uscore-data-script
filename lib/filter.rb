require 'pry'

module DataScript
  class Filter
    def self.filter!(bundles)
      organization_bundle = bundles.find {|b| b.entry.first.resource.resourceType == 'Organization'}
      practitioner_bundle = bundles.find {|b| b.entry.first.resource.resourceType == 'Practitioner'}
      patient_bundles = bundles.select {|b| b.entry.first.resource.resourceType == 'Patient'}

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
    end

    def self.get_resources_associated_with_encounter(bundle, encounter_urn)
      resources = []
      refd_medications = []
      refd_conditions = []
      refd_related_person = []

      bundle.entry.each do |entry|
        if entry.resource.respond_to?(:encounter) && entry.resource.encounter&.reference == encounter_urn
          resources << entry.resource
          refd_medications << entry.resource&.medicationReference&.reference if entry.resource.respond_to?(:medicationReference)
          refd_conditions << entry.resource&.reasonReference&.first&.reference if entry.resource.respond_to?(:reasonReference)
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

  end
end
