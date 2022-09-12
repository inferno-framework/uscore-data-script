# frozen_string_literal: true

require 'base64'
require 'securerandom'
require_relative 'constraints'
require_relative '../choice_type_creator'
require 'fhir_models'
require 'time'

module DataScript
  class Modifications
    DESIRED_MAX = 20
    # SOCIAL HISTORY are SDOH related, but not captured in SURVEYS like PRAPARE
    # These are SNOMED codes
    SDOH_CONDITIONS = ['105531004','10939881000119100','160701002','160903007','160904001','160968000','224295006','224299000','224355006','266934004','266948004','32911000','361055000','422650009','423315002','424393004','446654005','5251000175109','706893006','713458007','73438004','73595000','741062008']
    CLINICAL_TEST_OBSERVATIONS = ['44963-7']

    # SURVEY is for surveys and screenings that are NOT SDOH related
    SURVEY_OBSERVATIONS = ['44249-1','44261-6','55757-9','55758-7','59453-1','59460-6','59461-4','61576-5','62337-1','69737-5','70274-6','71933-6','71934-4','71956-7','71958-3','71960-9','71962-5','71964-1','71966-6','71968-2','71970-8','71972-4','71973-2','71974-0','71975-7','71976-5','71977-3','71978-1','71979-9','71980-7','72009-4','72010-2','72011-0','72012-8','72013-6','72014-4','72015-1','72016-9','72091-2','72092-0','72093-8','72094-6','72095-3','72096-1','72097-9','72098-7','72099-5','72100-1','72101-9','72102-7','72109-2','75626-2','76499-3','76504-0','82666-9','82667-7','89204-2','89206-7']
    # SDOH ASSESSMENTS include thiings like PRAPARE and other HRSN screenings.
    # There are 47 specific codes in the ValueSet expansion...
    SDOH_ASSESSMENT_OBSERVATIONS = ['93028-9','93025-5','69861-3','93027-1','81375-8','93034-7','68516-4','96782-8','93029-7','68517-2','96842-0','88123-5','76501-6','95618-5','93038-8','69858-9','93159-2','96780-2','44250-9','68524-8','88121-9','93026-3','82589-3','89555-7','96781-0','95530-2','56799-0','63586-2','96779-4','93677-3','63512-8','76437-3','88124-3','32624-9','97023-6','93035-4','54899-0','93033-9','93031-3','56051-6','88122-7','93030-5','97027-7','71802-3','44255-8','67875-5','76513-1']
    QUESTIONNAIRE_PRAPARE = 'http://hl7.org/fhir/us/sdoh-clinicalcare/Questionnaire/SDOHCC-QuestionnairePRAPARE'

    def self.modify!(results, random_seed = 3)
      FHIR.logger.level = :info

      # Create a random number generator, to pass to things that need randomness
      rng = Random.new(random_seed)
      # results is an Array of FHIR::Bundle objects,
      # where the first resource is a Patient.

      # Remove unwanted patient extensions and identifers
      results.each do |bundle|
        if bundle.entry.first.resource.resourceType == 'Patient'
          # first, remove unwanted patient extensions
          bundle.entry.first.resource.extension.delete_if do |extension|
            extension.url.start_with? 'http://synthetichealth.github.io'
          end

          # next, remove unwanted patient identifier
          bundle.entry.first.resource.identifier.delete_if do |identifier|
            identifier.system.start_with? 'http://standardhealthrecord.org'
          end

          # make sure every patient has a postalCode
          # some towns do not have postalCodes
          bundle.entry.first.resource.address.first.postalCode = '01999' unless bundle.entry.first.resource.address.first.postalCode

          # finally, make sure every patient has an address period
          bundle.entry.first.resource.address.first.period = FHIR::Period.new
          bundle.entry.first.resource.address.first.period.start = bundle.entry.first.resource.birthDate
        else
          # Not a patient bundle, probably contains Organizations, Locations, Practitioners, and/or PractitionerRoles
          # Remove unwanted extensions
          bundle.entry.each do |entry|
            entry.resource.extension.delete_if { |extension| extension.url.start_with? 'http://synthetichealth.github.io' }
          end
        end
      end

      # Make sure there aren't stupid numbers of every resource type
      # missing_profiles = DataScript::Constraints::REQUIRED_PROFILES.dup
      # puts '  - Removing resources...'
      # all_deleted_ids = []
      # results.each do |bundle|
      #   resource_counts = get_resource_counts(bundle)
      #   provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }&.resource
      #   next unless provenance
      #   resource_counts.each do |type, count|
      #     next unless count >= DESIRED_MAX

      #     deleted_ids = []
      #     medication_refs = get_medreqs_with_med_references(bundle)
      #     references = (dr_observations + dr_notes + encounter_refs + reason_refs + addresses_refs + medication_refs).compact.uniq
      #     bundle.entry.find_all { |e| e.resource.resourceType == type }.shuffle(random: rng).each do |e|
      #       break if deleted_ids.count >= (count - DESIRED_MAX)

      #       profiles = e.resource&.meta&.profile || []

      #       # Only delete it if it's not somehow important
      #       if !references.include?(e.resource.id) &&
      #          !(e.resource.is_a?(FHIR::Observation) && e.resource&.code&.text.start_with?('Tobacco smoking status')) &&
      #          (missing_profiles & profiles).empty?
      #         deleted_ids << e.resource.id
      #       elsif !(missing_profiles & profiles).empty?
      #         missing_profiles -= profiles
      #       end
      #     end
      #     bundle.entry.delete_if { |e| deleted_ids.include? e.resource.id }
      #     remove_provenance_targets(deleted_ids, provenance)
      #     all_deleted_ids.append(deleted_ids)
      #   end
      # end
      # puts "    - Removed #{all_deleted_ids.flatten.uniq.count} resources from #{results.length} Bundles."

      # add reaction.manifestation to allergy intolerance result because of must support changes in 3.1.1
      already_contains_reaction_manifestation =
        results.any? do |bundle|
          bundle
            .entry
            .select { |e| e.resource.is_a? FHIR::AllergyIntolerance }
            .map(&:resource)
            .any? do |resource|
              resource.reaction.any? { |reaction| reaction.manifestation.any? }
            end
        end
      unless already_contains_reaction_manifestation
        results.each do |bundle|
          allergy_intoleranace_resource = bundle.entry.find { |e| e.resource.is_a? FHIR::AllergyIntolerance }&.resource
          next if allergy_intoleranace_resource.nil?

          reaction = FHIR::AllergyIntolerance::Reaction.new
          manifestation = create_codeable_concept('http://snomed.info/sct', '271807003', 'Eruption of skin (disorder)')
          reaction.manifestation << manifestation
          allergy_intoleranace_resource.reaction << reaction
          puts "  - Altered AllergyIntolerance: #{allergy_intoleranace_resource.id}"
          break
        end
      end

      # Add a ServiceRequest for each CarePlan
      service_requests_for_careplans = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'CarePlan'
          # Add a ServiceRequest
          encounter = get_resource_by_id(bundle, entry.resource.encounter.reference)
          service_request = FHIR::ServiceRequest.new({
            id: SecureRandom.uuid,
            meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-servicerequest' ] },
            category: [{ coding: [{
              system: 'http://snomed.info/sct',
              code: '409073007',
              display: 'Education'
            }]}],
            code: entry.resource.category.last,
            subject: entry.resource.subject,
            encounter: entry.resource.encounter,
            requester: encounter&.participant&.first&.individual,
            status: entry.resource.status,
            intent: 'order',
            occurrencePeriod: entry.resource.period,
            authoredOn: entry.resource.period.start
          })
          service_request_reference = FHIR::Reference.new
          service_request_reference.reference = "urn:uuid:#{service_request.id}"
          provenance.target << service_request_reference
          bundle.entry << create_bundle_entry(service_request)
          service_requests_for_careplans += 1
        end
      end
      if service_requests_for_careplans > 0
        puts ("  - Generated #{service_requests_for_careplans} service requests for CarePlans.")
      else
        error("    * Unable to find a CarePlan to make an service request.")
      end

      # Add a RelatedPerson to each CareTeam
      related_person_for_careteam = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        careteam = bundle.entry.find { |e| e.resource.is_a? FHIR::CareTeam }&.resource
        next if careteam.nil?
        # Add a RelatedPerson
        related_person = FHIR::RelatedPerson.new({
          id: SecureRandom.uuid,
          meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-relatedperson' ] },
          active: (careteam.status == 'active'),
          patient: careteam.subject,
          relationship: [{ coding: [{
            system: 'http://terminology.hl7.org/CodeSystem/v3-RoleCode',
            code: 'ROOM',
            display: 'Roommate'
          }]}],
          name: [{
            use: 'official',
            family: 'Jefferson174',
            given: [ 'Ronald408', 'MacGyver246' ],
            prefix: [ 'Mr.' ]
          }],
          telecom: bundle.entry.first.resource.telecom,
          address: bundle.entry.first.resource.address
        })
        related_person_reference = FHIR::Reference.new
        related_person_reference.reference = "urn:uuid:#{related_person.id}"
        provenance.target << related_person_reference
        bundle.entry << create_bundle_entry(related_person)
        careteam.participant << FHIR::CareTeam::Participant.new({
          role: [ {
            coding: [ {
              system: 'http://snomed.info/sct',
              code: '133932002',
              display: 'Caregiver (person)'
            } ],
            text: 'Caregiver (person)'
          } ],
          member: related_person_reference
        })
        related_person_for_careteam += 1
      end
      if related_person_for_careteam > 0
        puts ("  - Generated #{related_person_for_careteam} RelatedPerson for CareTeams.")
      else
        error("    * Unable to find a CareTeam to add a RelatedPerson into.")
      end

      # Add discharge disposition to every encounter referenced by a medicationRequest of each record
      # This is necessary (rather than just one) because of how Inferno Program has to get Encounters
      results.each do |bundle|
        encounter_urls = bundle.entry.find_all { |e| e.resource.resourceType == 'MedicationRequest' }.map { |e| e.resource&.encounter&.reference }.compact.uniq
        encounter_urls.each do |encounter_url|
          encounter_entry = bundle.entry.find { |e| e.fullUrl == encounter_url }
          encounter = encounter_entry.resource
          encounter.hospitalization = FHIR::Encounter::Hospitalization.new
          encounter.hospitalization.dischargeDisposition = create_codeable_concept('http://www.nubc.org/patient-discharge','01','Discharged to home care or self care (routine discharge)')
        end
      end

      # Make sure at least one organization has an NPI
      result = results.find {|b| DataScript::Constraints.has(b, FHIR::Organization)}
      organization_entry = result.entry.find { |e| e.resource.resourceType == 'Organization' }
      organization = organization_entry.resource
      # Add a 10 digit NPI
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'http://hl7.org/fhir/sid/us-npi'
      organization.identifier.last.value = '9999999999'
      # Add a CLIA
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'urn:oid:2.16.840.1.113883.4.7'
      organization.identifier.last.value = '9999999999'

      # Add a PractitionerRole.endpoint
      result = results.find {|b| DataScript::Constraints.has(b, FHIR::PractitionerRole)}
      pr_entry = result.entry.find { |e| e.resource.resourceType == 'PractitionerRole' }
      pr = pr_entry.resource
      pr.endpoint = [ FHIR::Reference.new ]
      pr.endpoint.first.reference = '#endpoint'
      pr.endpoint.first.type = 'Endpoint'
      endpoint = FHIR::Endpoint.new
      endpoint.id = 'endpoint'
      endpoint.status = 'active'
      endpoint.connectionType = create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-connection-type', 'direct-project', 'Direct Project').coding.first
      endpoint.payloadType = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-payload-type', 'any', 'Any') ]
      endpoint.address = "mailto:#{pr.telecom.last.value}"
      pr.contained = [endpoint]

      # select by smoking status
      selection_smoker = results.find {|b| DataScript::Constraints.smoker(b)}
      unless selection_smoker
        # if there is no smoker, choose the oldest patient
        # and make them start smoking at the end of their life...
        # because why not?
        patient_results = results.find_all {|b| b.entry.first.resource.resourceType == 'Patient'}
        oldest = patient_results.sort {|a,b| a.entry.first.resource.birthDate <=> b.entry.first.resource.birthDate }.first
        alter_smoking_status(oldest)
        puts "  - Altered Smoker:     #{oldest.entry.first.resource.id}"
      end

      # sort the results by number of Conditions
      results.sort! do |a,b|
        count_a = a.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_b = b.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_a <=> count_b
      end
      # select the person with the most Conditions
      selection_conditions = results.last
      altered = alter_condition(selection_conditions, rng)
      puts "  - Altered Condition:  #{altered.id}"

      puts '  - Rewriting Condition Profiles for v5...'
      social_history_obs_inserted = 0
      this_or_that = true
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'Condition'
          category = entry.resource.category&.first&.coding&.first&.code
          if SDOH_CONDITIONS.include?(entry.resource.code&.coding&.first&.code)
            entry.resource.meta.profile[0] = 'http://hl7.org/fhir/us/core//StructureDefinition/us-core-condition-problems-health-concerns'
            entry.resource.category = []
            if this_or_that
              entry.resource.category << create_codeable_concept('http://terminology.hl7.org/CodeSystem/condition-category', 'problem-list-item', 'Problem List Item')
            else
              entry.resource.category << create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/condition-category', 'health-concern', 'Health Concern')
            end
            this_or_that = !this_or_that
            entry.resource.category << create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/us-core-tags', 'sdoh', 'SDOH')

            # Also make an social-history observation for this finding...
            social_history_obs = FHIR::Observation.new({
              id: SecureRandom.uuid,
              meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-social-history' ] },
              category: [{ coding: [{
                system: 'http://terminology.hl7.org/CodeSystem/observation-category',
                code: 'social-history',
                display: 'Social History'
              }]},{ coding: [{
                system: 'http://hl7.org/fhir/us/core/CodeSystem/us-core-tags',
                code: 'sdoh',
                display: 'SDOH'
              }]}],
              code: entry.resource.code,
              subject: entry.resource.subject,
              encounter: entry.resource.encounter,
              status: 'final',
              effectiveDateTime: entry.resource.onsetDateTime,
              valueBoolean: true
            })
            social_history_obs_reference = FHIR::Reference.new
            social_history_obs_reference.reference = "urn:uuid:#{social_history_obs.id}"
            provenance.target << social_history_obs_reference
            bundle.entry << create_bundle_entry(social_history_obs)
            social_history_obs_inserted += 1
          elsif category == 'encounter-diagnosis'
            entry.resource.meta.profile[0] = 'http://hl7.org/fhir/us/core//StructureDefinition/us-core-condition-encounter-diagnosis'
          end
          entry.resource.extension << asserted_date(entry.resource.recordedDate)
        end
      end
      puts ("    - Added #{social_history_obs_inserted} social-history observations based on SNOMED codes.")

      # select someone with the most numerous gender
      # from the people remaining, and remove their name
      unless MRBURNS
        selection_name = pick_by_gender(results)
        remove_name(selection_name)
        puts "  - Altered Name:       #{selection_name.entry.first.resource.id}"
      end

      # select by clinical note
      selection_note = results.find {|b| DataScript::Constraints.has(b, FHIR::DocumentReference)}
      if selection_note
        # modify it to have a URL rather than base64 encoded data
        docref = selection_note.entry.reverse.find { |e| e.resource.resourceType == 'DocumentReference' }.resource
        report = selection_note.entry.reverse.find { |e|
          e&.resource&.resourceType == 'DiagnosticReport' &&
            e&.resource&.presentedForm&.first&.data == docref&.content&.first&.attachment&.data }&.resource
        url = 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
        docref.content.first.attachment.contentType = 'application/pdf'
        docref.content.first.attachment.data = nil
        docref.content.first.attachment.url = url
        report.presentedForm.first.contentType = 'application/pdf'
        report.presentedForm.first.data = nil
        report.presentedForm.first.url = url
        puts "  - Altered DocumentReference URL: #{docref.id}"
        puts "  - Altered DiagnosticReport  URL: #{report.id}"
      else
        error('  * FAILED to find DocumentReference!')
      end

      # collect all the clinical notes and modify codes so we have at least one of each type
      category_types = [
        [ 'Cardiology', 'LP29708-2' ],
        [ 'Pathology', 'LP7839-6' ],
        [ 'Radiology', 'LP29684-5' ]
      ]
      note_types = [
        [ 'Consult note', '11488-4' ],
        [ 'Discharge summary', '18842-5' ],
        [ 'History and physical note', '34117-2' ],
        [ 'Procedure note', '28570-0' ],
        [ 'Progress note', '11506-3' ],
        [ 'Diagnostic imaging study', '18748-4' ],
        [ 'Laboratory report', '11502-2' ],
        [ 'Pathology study', '11526-1' ],
        [ 'Referral note', '57133-1' ],
        [ 'Surgical operation note', '11504-8' ],
        [ 'Nurse Note', '34746-8' ]
      ]
      category_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      note_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      # grab all the clinical notes
      all_docref = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DocumentReference'}.map {|e| e.resource} }.flatten
      all_report = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DiagnosticReport'}.map {|e| e.resource} }.flatten
      # there are more DiagnosticReports than DocumentReferences,
      # so we need to filter them...
      docref_data = all_docref.map {|r| r.content.first.attachment.data}
      matching_report = all_report.select { |r| r.presentedForm.length >= 1 && docref_data.include?(r.presentedForm.first.data) }

      # need to replace the codes...
      # we will use a uniform distribution of note_types
      note_types_index = 0
      category_types_index = 0
      all_docref.zip(matching_report).each do |docref, report|
        break if report.nil?
        docref.type = note_types[note_types_index]
        report.category = [ category_types[category_types_index] ]
        report.code = note_types[note_types_index]
        note_types_index += 1
        category_types_index += 1
        note_types_index = 0 if note_types_index >= note_types.length
        category_types_index = 0 if category_types_index >= category_types.length
      end
      puts "  - Altered codes for #{all_docref.length} clinical notes."

      all_docref.each do |docref|
        docref&.identifier&.each {|id| id.value = "urn:uuid:#{id.value}" if (id.system == 'urn:ietf:rfc:3986' && !id.value&.start_with?('urn'))}
      end
      puts "  - Altered identifiers for #{all_docref.length} clinical notes."

      # select by medication
      selection_medication = results.find {|b| DataScript::Constraints.has(b, FHIR::Medication)}
      unless selection_medication
        # if there is no free-standing Medication resource, we need to make one.
        med_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::MedicationRequest) }
        medreq = med_bundle.entry.find { |e| e.resource.resourceType == 'MedicationRequest' }
        provenance = med_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the medication
        med = FHIR::Medication.new
        med.id = SecureRandom.uuid
        med.status = 'active'
        med.meta = FHIR::Meta.new
        med.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication' ]
        med.code = medreq.resource.medicationCodeableConcept
        # alter the MedicationRequest to refer to the Medication resource and not a code
        medreq.resource.reportedBoolean = true
        medreq.resource.medicationCodeableConcept = nil
        medreq.resource.medicationReference = FHIR::Reference.new
        medreq.resource.medicationReference.reference = "urn:uuid:#{med.id}"
        medreq.resource.status = 'active'
        # add the Medication as a new Bundle entry
        med_bundle.entry << create_bundle_entry(med)
        # add the Medication into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{med.id}"
        puts "  - Altered Medication: #{med_bundle.entry.first.resource.id}"
      end

      # change one medication request from an order to a self prescription, if needed
      # we need at least two intents in order to demonstrate the multi-or search requirement for intent
      any_non_order = results.any? {|b| b.entry.any?{|e| e.resource.resourceType == 'MedicationRequest' && e.resource.intent != 'order' }}
      selection_medication_request = results.find {|b| DataScript::Constraints.has(b, FHIR::MedicationRequest)}
      if !any_non_order && selection_medication_request
        changed_medication = selection_medication_request.entry.select { |e| e.resource.resourceType == 'MedicationRequest'}.last.resource
        changed_medication.intent = 'plan'
        changed_medication.reportedBoolean = true
        changed_medication.reportedReference = nil
        changed_medication.requester = changed_medication.subject.clone
        changed_medication.encounter = nil
        puts "  - Altered Medication Request to have 'plan' intent: #{changed_medication.id}"
      end

      # select by device
      selection_device = results.find {|b| DataScript::Constraints.has(b, FHIR::Device)}
      if selection_device
        # if there is a Device resource, we need to clone it and use carrierAIDC.
        device = selection_device.entry.find { |e| e.resource.resourceType == 'Device' }
        provenance = selection_device.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the new Device
        dev = FHIR::Device.new(device.resource.to_hash)
        dev.id = SecureRandom.uuid
        dev.udiCarrier.first.carrierHRF = nil
        barcode_file_path = File.join(File.dirname(__FILE__), '../barcode.png')
        barcode_file = File.open(barcode_file_path, 'rb')
        barcode_data = barcode_file.read
        barcode_file.close
        dev.udiCarrier.first.carrierAIDC = Base64.encode64(barcode_data)
        # add the Device as a new Bundle entry
        selection_device.entry << create_bundle_entry(dev)
        # add the Device into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{dev.id}"
        puts "  - Cloned Device: #{selection_device.entry.first.resource.id}"
      end

      # select an Immunization
      selection_immunization = results.find {|b| DataScript::Constraints.has(b, FHIR::Immunization)}
      if selection_immunization
        # if there is an Immunization resource, we need to clone it and use carrierAIDC.
        immunization_entry = selection_immunization.entry.find { |e| e.resource.resourceType == 'Immunization' }
        immunization = immunization_entry.resource
        immunization.vaccineCode = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        immunization.statusReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-ActReason', 'OSTOCK', 'product out of stock')
        immunization.status = 'not-done'
        puts "  - Altered Immunization: #{selection_immunization.entry.first.resource.id}"
      end

      # select Bundle with Pulse Oximetry
      selection_pulse_ox = results.find {|b| DataScript::Constraints.has_pulse_ox(b)}
      if selection_pulse_ox
        provenance = selection_pulse_ox.entry.find { |e| e.resource.resourceType == 'Provenance' }
        pulse_ox_entry = selection_pulse_ox.entry.find {|e| e.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry' }
        pulse_ox_clone = nil
        2.times do
          pulse_ox_clone = FHIR.from_contents(pulse_ox_entry.resource.to_json)
          pulse_ox_clone.id = SecureRandom.uuid
          # Add the must support components
          pulse_ox_clone.component = []
          # First component is flow rate
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3151-8', 'Inhaled oxygen flow rate')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 6
          pulse_ox_clone.component.last.valueQuantity.unit = 'L/min'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = 'L/min'
          # Second component is concentration
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3150-0', 'Inhaled oxygen concentration')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 40
          pulse_ox_clone.component.last.valueQuantity.unit = '%'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = '%'
          # add the Pulse Oximetry as a new Bundle entry
          selection_pulse_ox.entry << create_bundle_entry(pulse_ox_clone)
          # add the Pulse Oximetry into the provenance
          provenance.resource.target << FHIR::Reference.new
          provenance.resource.target.last.reference = "urn:uuid:#{pulse_ox_clone.id}"
        end
        # for the second clone, data absent reason the components
        pulse_ox_clone.component.each do |component|
          component.valueQuantity = nil
          component.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        end
        puts "  - Cloned Pulse Oximetry and Added Components: #{selection_pulse_ox.entry.first.resource.id}"
      end

      goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Goal) }
      unless goal_bundle
        goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Patient) }
        goal = FHIR::Goal.new
        goal.meta = FHIR::Meta.new
        goal.meta.profile = ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal']
        goal.id = SecureRandom.uuid
        goal.lifecycleStatus = 'active'
        goal.description = create_codeable_concept('http://snomed.info/sct', '281004', 'Dementia associated with alcoholism (disorder)')
        goal.subject = { reference: "urn:uuid:#{DataScript::Constraints.patient(goal_bundle).id}" }
        goal_target = FHIR::Goal::Target.new
        goal_target.dueDate = Time.now.strftime("%Y-%m-%d")
        goal.target << goal_target
        goal_bundle.entry << create_bundle_entry(goal)
        goal_provenance = goal_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        goal_provenance.resource.target << FHIR::Reference.new
        goal_provenance.resource.target.last.reference = "urn:uuid:#{goal.id}"
      end

      observation_values_found = {
        'valueQuantity' => false,
        'valueCodeableConcept' => false,
        'valueString' => false
      }
      observation_profiles_valueCodeableConcept_required = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus'
      ]
      observation_profiles_components_required = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-blood-pressure' #'http://hl7.org/fhir/StructureDefinition/bp'
      ]
      observation_profiles = [
        #'http://hl7.org/fhir/us/core/StructureDefinition/us-core-vital-signs', # vital-signs is more or less an abstract profile
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-bmi', #'http://hl7.org/fhir/StructureDefinition/bmi',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-head-circumference',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-height', #'http://hl7.org/fhir/StructureDefinition/bodyheight',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-weight', #'http://hl7.org/fhir/StructureDefinition/bodyweight',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-temperature', #'http://hl7.org/fhir/StructureDefinition/bodytemp',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-heart-rate', #'http://hl7.org/fhir/StructureDefinition/heartrate',
        'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
        'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
        'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-respiratory-rate', #'http://hl7.org/fhir/StructureDefinition/resprate',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-imaging'
      ]
      # Add missing Head Circumference Percent resource
      unless DataScript::Constraints.has_headcircum(results)
        headcircum_resource = FHIR::Observation.new({
          id: SecureRandom.uuid,
          meta: {
            profile: [
              'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
              'http://hl7.org/fhir/StructureDefinition/vitalsigns'
            ]
          },
          category: [
            {
              coding: [
                {
                  code: 'vital-signs',
                  system: 'http://terminology.hl7.org/CodeSystem/observation-category',
                  display: 'Vital Signs'
                }
              ]
            }
          ],
          code: {
            coding: [
              {
                code: '8289-1',
                system: 'http://loinc.org',
                display: 'Head Occipital-frontal circumference Percentile'
              }
            ]
          },
          subject: {
            reference: "urn:uuid:#{DataScript::Constraints.patient(results.first).id}"
          },
          status: 'final',
          effectiveDateTime: (DateTime.strptime(DataScript::Constraints.patient(results.first).birthDate, '%Y-%m-%d') + 30).iso8601,
          valueQuantity: {
            value: 23,
            unit: '%',
            system: 'http://unitsofmeasure.org',
            code: '%'
          }
        })
        results.first.entry.push create_bundle_entry(headcircum_resource)
        provenance = results.first.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        provenance.target << FHIR::Reference.new
        provenance.target.last.reference = "urn:uuid:#{headcircum_resource.id}"
      end

      puts '  - Adding Observation Imaging Results and ServiceRequests for each ImagingStudy...'
      imaging_study_codes = [
        ['18782-3','Radiology Study observation (narrative)'],
        ['19005-8','Radiology Imaging study [Impression] (narrative)'],
        ['18834-2','Radiology Comparison study (narrative)']
      ]
      imaging_study_obs_added = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'ImagingStudy'
          # Add an Observation Imaging Result
          code = imaging_study_codes.sample
          imaging_study_obs = FHIR::Observation.new({
            id: SecureRandom.uuid,
            meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-imaging' ] },
            category: [{ coding: [{
              system: 'http://terminology.hl7.org/CodeSystem/observation-category',
              code: 'imaging',
              display: 'Imaging'
            }]}],
            code: { coding: [{
              system: 'http://loinc.org',
              code: code.first,
              display: code.last
            }]},
            subject: entry.resource.subject,
            encounter: entry.resource.encounter,
            status: 'final',
            effectiveDateTime: entry.resource.started,
            valueString: "#{entry.resource.procedureCode.first.text} results: abnormal"
          })
          imaging_study_obs_reference = FHIR::Reference.new
          imaging_study_obs_reference.reference = "urn:uuid:#{imaging_study_obs.id}"
          provenance.target << imaging_study_obs_reference
          bundle.entry << create_bundle_entry(imaging_study_obs)
          imaging_study_obs_added += 1

          # Add a ServiceRequest
          encounter = get_resource_by_id(bundle, entry.resource.encounter.reference)
          service_request = FHIR::ServiceRequest.new({
            id: SecureRandom.uuid,
            meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-servicerequest' ] },
            category: [{ coding: [{
              system: 'http://snomed.info/sct',
              code: '363679005',
              display: 'Imaging'
            }]}],
            code: entry.resource.procedureCode.first,
            subject: entry.resource.subject,
            encounter: entry.resource.encounter,
            requester: encounter&.participant&.first&.individual,
            status: 'completed',
            intent: 'order',
            occurrenceDateTime: entry.resource.started,
            authoredOn: entry.resource.started
          })
          service_request_reference = FHIR::Reference.new
          service_request_reference.reference = "urn:uuid:#{service_request.id}"
          provenance.target << service_request_reference
          bundle.entry << create_bundle_entry(service_request)
        end
      end
      if imaging_study_obs_added > 0
        puts ("    - Generated #{imaging_study_obs_added} each: observation imaging results, and service requests.")
      else
        error("    * Unable to find an ImagingStudy to make an observation imaging result.")
      end

      puts '  - Relabeling Clinical Test Observations...'
      relabeled_clinical_test_obs = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'Observation'
          if CLINICAL_TEST_OBSERVATIONS.include?(entry.resource.code.coding.first.code)
            entry.resource.meta = FHIR::Meta.new
            entry.resource.meta.profile = ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-clinical-test']
            entry.resource.category = [ create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/us-core-observation-category', 'clinical-test', 'Clinical Test') ]
            relabeled_clinical_test_obs += 1
          end
        end
      end
      if relabeled_clinical_test_obs > 0
        puts ("    - Relabeled #{relabeled_clinical_test_obs} clinical test observations.")
      else
        puts ("    * Unable to find an clinical test observation to relabel (this is not an error).")
      end

      puts '  - Generating Clinical Test Observations for some Procedures...'
      generated_clinical_test_obs = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        last_encounter = bundle.entry.reverse.find { |e| e.resource.is_a? FHIR::Encounter }.resource
        walk_test_obs = FHIR::Observation.new({
          id: SecureRandom.uuid,
          meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-clinical-test' ] },
          category: [{ coding: [{
            system: 'http://hl7.org/fhir/us/core/CodeSystem/us-core-observation-category',
            code: 'clinical-test',
            display: 'Clinical Test'
          }]}],
          code: { coding: [{
            system: 'http://loinc.org',
            code: '64098-7',
            display: 'Six minute walk test'
          }]},
          subject: last_encounter.subject,
          encounter: { reference: "urn:uuid:#{last_encounter.id}" },
          status: 'final',
          effectivePeriod: last_encounter.period,
          valueQuantity: {
            value: ((300 * rand) + 400).to_i,
            unit: 'm/(6.min)',
            system: 'http://unitsofmeasure.org',
            code: 'm/(6.min)'
          }
        })
        walk_test_obs_reference = FHIR::Reference.new
        walk_test_obs_reference.reference = "urn:uuid:#{walk_test_obs.id}"
        provenance.target << walk_test_obs_reference
        bundle.entry << create_bundle_entry(walk_test_obs)
        generated_clinical_test_obs += 1
      end
      if generated_clinical_test_obs > 0
        puts ("    - Generated #{generated_clinical_test_obs} clinical test observations.")
      else
        error("    * Unable to find an Encounter to add a walk test onto.")
      end

      sexual_orientation_codes = [
        create_codeable_concept('http://snomed.info/sct', '38628009', 'Homosexuality'),
        create_codeable_concept('http://snomed.info/sct', '20430005', 'Heterosexual state'),
        create_codeable_concept('http://snomed.info/sct', '42035005', 'Bisexual state'),
        create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-NullFlavor', 'OTH', 'Other'),
        create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-NullFlavor', 'UNK', 'Unknown'),
        create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-NullFlavor', 'ASKU', 'Asked but no answer')
      ]
      puts '  - Preprocessing PRAPARE Observations...'
      prapare_count = 0
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        sexual_orientation = sexual_orientation_codes.sample
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'Observation'
          code = entry.resource.code&.coding&.first&.code
          if code == '93025-5' # PRAPARE Multi-Observation
            # Create a QuestionnaireResponse
            questionnaireResponse, serviceRequest = create_questionnaire_response_from_multiobservation(entry.resource)
            questionnaireResponseReference = FHIR::Reference.new
            questionnaireResponseReference.reference = "urn:uuid:#{questionnaireResponse.id}"
            provenance.target << questionnaireResponseReference
            bundle.entry << create_bundle_entry(questionnaireResponse)
            if serviceRequest
              serviceRequestReference = FHIR::Reference.new
              serviceRequestReference.reference = "urn:uuid:#{serviceRequest.id}"
              provenance.target << serviceRequestReference
              bundle.entry << create_bundle_entry(serviceRequest)
            end

            entry.resource.meta = FHIR::Meta.new
            entry.resource.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sdoh-assessment' ]
            entry.resource.category = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/observation-category','survey','Survey') ]
            entry.resource.category << create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/us-core-tags', 'sdoh', 'SDOH')
            entry.resource.hasMember = []
            entry.resource.derivedFrom = [ questionnaireResponseReference ]
            entry.resource.component.each do |component|
              instance = FHIR::Observation.new
              instance.id = SecureRandom.uuid
              instance.component = nil
              instance.meta = FHIR::Meta.new
              instance.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sdoh-assessment' ]
              instance.category = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/observation-category','survey','Survey') ]
              instance.category << create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/us-core-tags', 'sdoh', 'SDOH')
              instance.code = component.code
              instance.derivedFrom = [ FHIR::Reference.new ]
              instance.derivedFrom.first.reference = entry.fullUrl
              if component.valueQuantity
                instance.valueQuantity = component.valueQuantity
              elsif component.valueString
                instance.valueString = component.valueString
              elsif component.valueCodeableConcept
                instance.valueCodeableConcept = component.valueCodeableConcept
              end
              instance.status = entry.resource.status
              instance.subject = entry.resource.subject
              instance.encounter = entry.resource.encounter
              instance.effectiveDateTime = entry.resource.effectiveDateTime
              instance.issued = entry.resource.issued
              reference = FHIR::Reference.new
              reference.reference = "urn:uuid:#{instance.id}"
              provenance.target << reference
              entry.resource.hasMember << reference
              bundle.entry << create_bundle_entry(instance)
            end
            prapare_count += 1

            # add a sexual orientation observation to the same encounter the PRAPARE questionnaire was administered...
            sexual_orientation_obs = FHIR::Observation.new({
              id: SecureRandom.uuid,
              meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sexual-orientation' ] },
              category: [{ coding: [{
                system: 'http://terminology.hl7.org/CodeSystem/observation-category',
                code: 'social-history',
                display: 'Social History'
              }]}],
              code: { coding: [{
                system: 'http://loinc.org',
                code: '76690-7',
                display: 'Sexual orientation'
              }]},
              subject: entry.resource.subject,
              encounter: entry.resource.encounter,
              status: 'final',
              effectiveDateTime: entry.resource.effectiveDateTime,
              valueCodeableConcept: sexual_orientation
            })
            sexual_orientation_reference = FHIR::Reference.new
            sexual_orientation_reference.reference = "urn:uuid:#{sexual_orientation_obs.id}"
            provenance.target << sexual_orientation_reference
            bundle.entry << create_bundle_entry(sexual_orientation_obs)
          end
        end
      end
      if prapare_count >  0
        puts "    - Rewrote #{prapare_count} PRAPARE Observations..."
      else
        error('    * Rewrote 0 PRAPARE Observations.')
      end

      puts '  - Rewriting Observation Profiles for v5...'
      obs_profiles = Hash.new(0)
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        bundle.entry.each do |entry|
          next unless entry.resource.resourceType == 'Observation'
          next if entry.resource.meta&.profile&.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sdoh-assessment')

          category = entry.resource.category&.first&.coding&.first&.code
          code = entry.resource.code&.coding&.first&.code
          if SURVEY_OBSERVATIONS.include?(code)
            profile = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-survey'
            entry.resource.meta = FHIR::Meta.new
            entry.resource.meta.profile = [ profile ]
            entry.resource.category = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/observation-category','survey','Survey') ]
            obs_profiles[profile] += 1
          elsif SDOH_ASSESSMENT_OBSERVATIONS.include?(code)
            profile = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sdoh-assessment'
            entry.resource.meta = FHIR::Meta.new
            entry.resource.meta.profile = [ profile ]
            entry.resource.category = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/observation-category','survey','Survey') ]
            entry.resource.category << create_codeable_concept('http://hl7.org/fhir/us/core/CodeSystem/us-core-tags', 'sdoh', 'SDOH')
            obs_profiles[profile] += 1
          elsif category == 'survey'
            # catch any remaining survey obs that weren't SDOH related...
            profile = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-survey'
            entry.resource.meta = FHIR::Meta.new
            entry.resource.meta.profile = [ profile ]
            entry.resource.category = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/observation-category','survey','Survey') ]
            obs_profiles[profile] += 1
          end
        end
      end
      obs_profiles.each do |profile,count|
        puts "    - Labeled #{count} instances of #{profile}"
      end

      puts '  - Processing Observation Data Absent Reasons'
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        break if observation_profiles.empty?
        observation_profiles.delete_if do |profile_url|
          entry = bundle.entry.find {|e| e.resource.resourceType == 'Observation' && e.resource.meta&.profile&.include?(profile_url) }
          if entry
            instance = FHIR::Json.from_json(entry.resource.to_json)
            instance.id = SecureRandom.uuid
            instance.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
            if observation_profiles_valueCodeableConcept_required.include?(profile_url)
              instance.valueCodeableConcept = instance.dataAbsentReason
              instance.dataAbsentReason = nil
            elsif observation_profiles_components_required.include?(profile_url)
              instance.component.each do |component|
                component.valueQuantity = nil
                component.dataAbsentReason = instance.dataAbsentReason
              end
            else
              instance.valueQuantity = nil
              instance.valueCodeableConcept = nil
              instance.valueString = nil
            end
            new_entry = create_bundle_entry(instance)
            provenance.target << FHIR::Reference.new
            provenance.target.last.reference = "urn:uuid:#{instance.id}"
            bundle.entry << new_entry
            puts "    - #{profile_url}: #{new_entry.fullUrl}"
            true # delete this profile url from the list
          else
            false # keep searching for this profile url in the next bundle
          end
        end
      end
      unless observation_profiles.empty?
        error('  * Missed Observation Data Absent Reasons')
        observation_profiles.each do |profile_url|
          error("    ** #{profile_url}")
        end
      end

      puts '  - Checking for Observation valueQuantity, valueCodeableConcept, and valueString...'
      results.each do |bundle|
        entries = bundle.entry.select {|entry| entry.resource.is_a?(FHIR::Observation)}
        observations = entries.map {|entry| entry.resource}
        # check for valueQuantity
        hasValue = observations.any? {|observation| observation.valueQuantity != nil }
        observation_values_found['valueQuantity'] = true if hasValue
        # check for valueCodeableConcept
        hasValue = observations.any? {|observation| observation.valueCodeableConcept != nil }
        observation_values_found['valueCodeableConcept'] = true if hasValue
        # check for valueString
        hasValue = observations.any? {|observation| observation.valueString != nil }
        observation_values_found['valueString'] = true if hasValue
        break if observation_values_found.values.all? { |value| value == true }
      end
      observation_values_found.each do |key, value|
        if value
          puts "    Found #{key}: #{value}"
        else
          error("    Found #{key}: #{value}")
        end
      end

      # remove all resources from bundles that are not US Core profiles
      results.each do |bundle|
        bundle.entry.delete_if {|e| ['Claim','ExplanationOfBenefit','ImagingStudy','MedicationAdministration','SupplyDelivery'].include?(e.resource.resourceType)}
      end
      puts '  - Removed resources out of scope for US Core.'
      # There are probably some observations remaining after this that are not US Core profiles,
      # but they likely are referenced from DiagnosticReports which are US Core profiled.

      # delete provenance references to removed resources
      results.each do |bundle|
        next if bundle.entry.first.resource.resourceType != 'Patient' # skip bundles of Organizations and Practitioners...
        provenance = bundle.entry.find {|e| e.resource.resourceType == 'Provenance' }.resource
        uuids = bundle.entry.map {|e| e.fullUrl}
        provenance.target.keep_if {|reference| uuids.include?(reference.reference) }
      end
      puts '  - Rewrote Provenance targets.'

      DataScript::ChoiceTypeCreator.check_choice_types(results)

      # DiagnosticReports need to have two performer types, so we add them here
      puts '  - Modifying DiagnosticReport performer types...'
      dr_bundle = results.find do |b|
        b.entry.any? do |e|
          e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta&.profile&.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
        end &&
          b.entry.any? do |e|
            e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta&.profile&.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
          end
      end
      dr_notes = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta&.profile&.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
      end.map {|e| e.resource }
      dr_labs = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta&.profile&.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
      end.map {|e| e.resource }
      practitioner_bundle = results.find {|b| b.entry.first.resource.resourceType == 'Practitioner'}
      dr_practitioner = practitioner_bundle.entry.find { |e| e.resource.is_a? FHIR::Practitioner }.resource.identifier.first
      organization_bundle = results.find {|b| b.entry.first.resource.resourceType == 'Organization'}
      dr_organization = organization_bundle.entry.find { |e| e.resource.is_a? FHIR::Organization }.resource.identifier.first
      puts "    + DiagnosticReport Practitioner ID: Practitioner?identifier=#{dr_practitioner.system}|#{dr_practitioner.value}"
      puts "    + DiagnosticReport Organization ID: Organization?identifier=#{dr_organization.system}|#{dr_organization.value}"
      dr_notes.concat(dr_labs).each do |dr|
        # "performer": [ {
        #   "reference": "Practitioner?identifier=http://hl7.org/fhir/sid/us-npi|9999105593",
        #   "display": "Dr. Fernanda589 Huel628"
        # } ],
        dr.performer << { reference: "Practitioner?identifier=#{dr_practitioner.system}|#{dr_practitioner.value}" }
        dr.performer << { reference: "Organization?identifier=#{dr_organization.system}|#{dr_organization.value}" }
      end

      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions, so we specifically return just this patient bundle.
      selection_name
    end

    def self.pick_by_gender(results)
      # pick someone of the more represented gender
      # in other words, if there are more males, pick a male.
      # otherwise if there are more females, pick a female.
      females = results.count {|b| b.entry.first.resource.resourceType == 'Patient' && b.entry.first.resource.gender == 'female'}
      males = results.count {|b| b.entry.first.resource.resourceType == 'Patient' && b.entry.first.resource.gender == 'male'}
      if males > females
        selection = results.find {|b| b.entry.first.resource.resourceType == 'Patient' && b.entry.first.resource.gender == 'male'}
      else
        selection = results.find {|b| b.entry.first.resource.resourceType == 'Patient' && b.entry.first.resource.gender == 'female'}
      end
      selection
    end

    def self.get_resource_by_id(bundle, id)
      entry = bundle.entry.find { |entry| entry.resource.id == id || entry.fullUrl == id }
      return entry.resource if entry
      nil
    end

    def self.remove_name(bundle)
      # Replace name with empty name.
      # Technically this doesn't validate because of us-core-8:
      # Patient.name.given or Patient.name.family or both SHALL be present [family.exists() or given.exists()]
      #
      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions.
      human_name = FHIR::HumanName.new
      # If the us-core-8 invariant changes to allow data absent reason on name, then we can enable the next line
      # human_name.extension = [ data_absent_reason ]
      bundle.entry.first.resource.name = [ human_name ]
    end

    def self.alter_condition(bundle, rng)
      # randomly pick one of their Conditions
      random_condition = bundle.entry.map {|e| e.resource }.select {|r| r.resourceType == 'Condition'}.sample(random: rng)
      # and replace the category with a data-absent-reason
      unknown = FHIR::CodeableConcept.new
      unknown.extension = [ data_absent_reason ]
      random_condition.category = [ unknown ]
      random_condition
    end

    def self.data_absent_reason
      extension = FHIR::Extension.new
      extension.url = 'http://hl7.org/fhir/StructureDefinition/data-absent-reason'
      extension.valueCode = 'unknown'
      extension
    end

    def self.asserted_date(date)
      extension = FHIR::Extension.new
      extension.url = 'http://hl7.org/fhir/StructureDefinition/condition-assertedDate'
      extension.valueDateTime = date.split('T').first
      extension
    end

    def self.alter_smoking_status(bundle)
      last_smoking_observation = bundle.entry.select {|e| e.resource.resourceType == 'Observation' && e.resource&.code&.text.start_with?('Tobacco smoking status') }.last.resource
      coding = FHIR::Coding.new
      coding.system = 'http://snomed.info/sct'
      coding.code = '449868002'
      coding.display = 'Current every day smoker'
      smoker = FHIR::CodeableConcept.new
      smoker.coding = [ coding ]
      smoker.text = 'Current every day smoker'
      last_smoking_observation.valueCodeableConcept = smoker
    end

    def self.create_codeable_concept(system, code, display)
      coding = FHIR::Coding.new
      coding.system = system
      coding.display = display
      coding.code = code
      codeableconcept = FHIR::CodeableConcept.new
      codeableconcept.text = display
      codeableconcept.coding = [ coding ]
      codeableconcept
    end

    def self.create_bundle_entry(resource)
      entry = FHIR::Bundle::Entry.new
      entry.fullUrl = "urn:uuid:#{resource.id}"
      entry.resource = resource
      entry.request = FHIR::Bundle::Entry::Request.new
      entry.request.local_method = 'POST'
      entry.request.url = resource.resourceType
      entry
    end

    PRAPARE_STRUCTURE = {
      '93025-5' => {
        '93043-8' => ['56051-6','32624-9','93035-4','93034-7','54899-0'],
        '93042-0'  => ['63512-8','71802-3','93033-9','56799-0'],
        '93041-2' => ['82589-3','67875-5','76437-3','63586-2','93031-3','93030-5'],
        '93040-4' => ['93029-7','93038-8'],
        '93039-6' => ['93028-9','93027-1','93026-3','76501-6']
      }
    }

    def self.create_questionnaire_response_from_multiobservation(observation)
      serviceRequests = nil
      questionnaireResponse = FHIR::QuestionnaireResponse.new
      questionnaireResponse.id = SecureRandom.uuid
      questionnaireResponse.meta = FHIR::Meta.new
      questionnaireResponse.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-questionnaireresponse' ]
      questionnaireResponse.meta.tag = [ FHIR::Coding.new ]
      questionnaireResponse.meta.tag.last.code = 'sdoh'
      questionnaireResponse.meta.tag.last.display = 'SDOH'
      questionnaireResponse.meta.tag.last.system = 'http://hl7.org/fhir/us/core/CodeSystem/us-core-tags'
      questionnaireResponse.questionnaire = 'http://hl7.org/fhir/us/sdoh-clinicalcare/Questionnaire/SDOHCC-QuestionnairePRAPARE'
      # TODO primitive extensiion 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-extension-questionnaire-uri'
      questionnaireResponse.status = 'completed'
      questionnaireResponse.subject = observation.subject
      questionnaireResponse.encounter = observation.encounter
      questionnaireResponse.authored = observation.issued
      results = process_prapare_structure(PRAPARE_STRUCTURE, observation)
      questionnaireResponse.item = results.first
      serviceRequests = results.last&.first
      [questionnaireResponse, serviceRequests]
    end

    def self.process_prapare_structure(structure, observation, prefix=nil)
      items = []
      serviceRequests = []
      if structure.is_a?(Hash)
        structure.each do |key,value|
          item = FHIR::QuestionnaireResponse::Item.new
          item.linkId = "#{prefix}/#{key}"
          component = observation.component.find {|c| c.code.coding.first.code == key}
          item.text = component.code.text if component
          prefix = value.is_a?(Array) ? "/#{key}" : nil
          results = process_prapare_structure(value, observation, prefix)
          item.item = results.first
          serviceRequests.append(results.last).flatten!
          items << item
        end
      elsif structure.is_a?(Array)
        structure.each do |key|
          item = FHIR::QuestionnaireResponse::Item.new
          item.linkId = "#{prefix}/#{key}"
          component = observation.component.find {|c| c.code.coding.first.code == key}
          item.text = component.code.text if component
          result = convert_obs_value_questionnaire_answer(component, observation)
          item.answer = [ result.first ]
          items << item
          serviceRequest = result.last
          serviceRequests << result.last unless result.last.nil?
        end
      end
      return items, serviceRequests
    end

    def self.convert_obs_value_questionnaire_answer(component, observation)
      answer = FHIR::QuestionnaireResponse::Item::Answer.new
      serviceRequest = nil
      if component.valueQuantity
        answer.valueQuantity = component.valueQuantity
      elsif component.valueCodeableConcept
        answer.valueCoding = component.valueCodeableConcept.coding.first
        # create a service request is this for food....
        if component.valueCodeableConcept.coding.first.code == 'LA30125-1' # Food
          serviceRequest = FHIR::ServiceRequest.new({
            id: SecureRandom.uuid,
            meta: { profile: [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-servicerequest' ] },
            category: [{ coding: [{
              system: 'http://hl7.org/fhir/us/core/CodeSystem/us-core-tags',
              code: 'sdoh',
              display: 'SDOH'
            }], text: 'Social Determinants Of Health'}],
            code: { coding: [{
              system: 'http://snomed.info/sct',
              code: '467771000124109',
              display: 'Assistance with application for food pantry program'
            }]},
            subject: observation.subject,
            encounter: observation.encounter,
            status: 'completed',
            intent: 'order',
            occurrenceDateTime: observation.issued,
            authoredOn: observation.issued
          })
        end
      elsif component.valueString
        answer.valueString = component.valueString
      end
      return answer, serviceRequest
    end

    def self.questionnaire_response_primitive_extension(json_string)
      find_string = '        "questionnaire": "http://hl7.org/fhir/us/sdoh-clinicalcare/Questionnaire/SDOHCC-QuestionnairePRAPARE",'
      replace_string = '        "questionnaire": "http://hl7.org/fhir/us/sdoh-clinicalcare/Questionnaire/SDOHCC-QuestionnairePRAPARE",
            "_questionnaire" : {
              "extension" : [
                {
                  "url" : "http://hl7.org/fhir/us/core/StructureDefinition/us-core-extension-questionnaire-uri",
                  "valueUri" : "https://prapare.org/wp-content/uploads/2021/10/PRAPARE-English.pdf"
                }
              ]
            },'
      json_string.gsub!(find_string, replace_string)
      json_string
    end
  end
end
