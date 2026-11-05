#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic offline extraction from saved, official public sources. No key,
# GitHub, Rails, database, or network request is used by this command.
require 'nokogiri'
require 'cgi'
require_relative 'lib/nicherank'

module NicheRank
  class PublicPreparation
    ROOT = File.expand_path('../..', __dir__)
    EXTRA = %w[unit eligibility_status eligibility_reason]
    ROSTER_HEADERS = %w[university name title homepage_url source_url]
    attr_reader :candidates

    def initialize(source_dir: File.join(ROOT, 'tmp/public_sources'), manual: File.join(ROOT, 'db/data/manual'))
      @source_dir, @manual, @candidates = source_dir, manual, []
    end

    def html(key)
      Nokogiri::HTML(File.read(File.join(@source_dir, "#{key}.html")), nil, 'UTF-8')
    end

    def url(key)
      metadata = File.join(@source_dir, "#{key}.meta.json")
      return JSON.parse(File.read(metadata)).fetch('url') if File.exist?(metadata)
      return 'https://cse.engin.umich.edu/people/faculty/' if key == 'michigan_browser'
      raise "Missing source metadata: #{key}"
    end

    def clean(value)
      CGI.unescapeHTML(value.to_s).gsub(/\s+/, ' ').strip
    end

    def add(university, name, title, homepage, source, unit: nil, decision: nil, reason: nil)
      return if name.to_s.strip.empty?
      @candidates << { 'university' => university, 'name' => clean(name), 'title' => clean(title),
                       'homepage_url' => homepage, 'source_url' => source, 'unit' => unit,
                       'eligibility_status' => decision, 'eligibility_reason' => reason }
    end

    def self.classify(title, school: nil)
      t = title.to_s.downcase
      regular_cs = t.split(';').any? { |part| part.match?(/professor|\bprof\b/) && part.match?(/computer science|eecs/) && !part.match?(/courtesy|adjunct|emerit|teach|practice|visit/) }
      return ['needs_review', 'No appointment title on directory; verify official profile'] if t.strip.empty?
      return ['excluded', 'Emeritus/retired appointment'] if t.match?(/emerit|retired/)
      return ['excluded', 'Teaching/lecturer/practice appointment'] if t.match?(/teach|lecturer|practice|tch\b/)
      return ['excluded', 'Adjunct or visiting appointment'] if t.match?(/adjunct|\badj\b|visiting/) && !regular_cs
      return ['excluded', 'Postdoctoral appointment'] if t.match?(/post.?doc|post doctoral/)
      return ['excluded', 'Courtesy/affiliate-only appointment'] if t.match?(/\A(?:courtesy|affiliated) faculty\z/)
      return ['excluded', 'Visiting appointment'] if t.match?(/visting/)
      return ['excluded', 'Courtesy-only CS appointment'] if t.match?(/(?:courtesy|affiliat).{0,40}(?:computer science|eecs)/) && !t.match?(/(?:professor|prof),? (?:of )?(?:computer science|eecs)[^;|]*(?:professor|prof)/)
      return ['excluded', 'Courtesy appointment'] if t.match?(/\(courtesy\)/) && school == 'University of Michigan' && !t.match?(/professor, eecs.{0,12}computer science/)
      return ['needs_review', 'Clinical appointment needs eligibility review'] if t.include?('clinical')
      return ['included', 'Eligible professor/research-faculty title in agreed unit roster'] if t.match?(/professor|\bprof\b|assoc prof|asst prof|research (?:scientist|faculty)/)
      return ['included', 'Research scientist classified as Faculty in official SCS feed'] if school == 'Carnegie Mellon University' && t.match?(/systems scientist/)
      ['needs_review', 'Directory title does not establish eligible academic appointment']
    end

    def stanford
      %w[stanford stanford_1 stanford_2].each do |key|
        doc = html(key)
        doc.css('.su-card__contents').each do |card|
          a = card.at_css('h3 a')
          next unless a
          heading = card.at_css('h3').text
          title = clean(card.text.sub(heading, ''))
          add('Stanford University', a.text, title, URI.join(url(key), a['href']).to_s, url(key), unit: 'Computer Science')
        end
      end
    end

    def uiuc
      key = 'uiuc_school'
      html(key).css('.item.person').each do |card|
        a = card.at_css('.name a')
        next unless a
        add('University of Illinois Urbana-Champaign', a.text, card.at_css('.title')&.text,
            URI.join(url(key), a['href']).to_s, url(key), unit: 'Siebel School of Computing and Data Science')
      end
    end

    def mit
      %w[mit_cs mit_ai].each do |key|
        html(key).css('.people-entry').each do |card|
          a = card.at_css('h5 a')
          next unless a
          add('Massachusetts Institute of Technology', a.text, card.at_css('> p')&.text, a['href'], url(key), unit: key == 'mit_cs' ? 'CS' : 'AI+D')
        end
      end
    end

    def berkeley
      key = 'berkeley_utf8'
      html(key).css('.cc-image-list__item__content').each do |card|
        a = card.at_css('h3 a')
        next unless a
        add('University of California Berkeley', a.text, card.at_css('p strong')&.text,
            URI.join(url(key), a['href']).to_s, url(key), unit: 'EECS CS faculty list')
      end
    end

    def uw
      key = 'uw'
      html(key).css('a[aria-label^="Read the bio"]').each do |a|
        container = a.ancestors.find { |n| n['class'].to_s.split.include?('e-con-inner') }
        headings = container ? container.css('.elementor-heading-title').map { |n| clean(n.text) } : []
        index = headings.index(clean(a.text))
        title = index ? headings[index + 1] : nil
        add('University of Washington', a.text, title, a['href'], url(key), unit: 'Allen School')
      end
    end

    def michigan
      key = 'michigan_browser'
      html(key).css('.eecs_person_wrapper').each do |card|
        last, first = clean(card.at_css('.eecs_person_name')&.text).split(',', 2)
        name = first ? "#{first.strip} #{last}" : last
        title = card.css('.person_title_section').map { |n| clean(n.text) }.join('; ')
        title = title.sub(/\b(?:he\/him\/his|she\/her\/hers|they\/them\/theirs)\b/, '').strip
        add('University of Michigan', name, title, card.at_css('a.person_web')&.[]('href') || url(key), url(key), unit: 'CSE')
      end
    end

    def cornell
      key = 'cornell_cs_0'
      html(key).css('.directory-card').each do |card|
        name = card.at_css('.name')
        next unless name
        roles = card.css('.field--name-field-profile-roles .field__item').map { |x| clean(x.text) }
        department_member = roles.include?('Faculty (Department)')
        title = card.css('.position-titles .field__item').map { |x| clean(x.text) }.join('; ')
        a = name.at_css('a')
        decision = department_member ? nil : 'excluded'
        add('Cornell University', name.text, title, a ? URI.join(url(key), a['href']).to_s : url(key), url(key),
            unit: roles.join('; '), decision: decision, reason: department_member ? nil : 'Field-only/adjunct/emeritus/visiting listing; not CS department faculty')
      end
    end

    def cmu
      key = 'cmu_all'
      allowed = ['Computer Science Department', 'Machine Learning Department', 'Robotics Institute', 'Language Technologies Institute',
                 'Human-Computer Interaction Institute', 'Software and Societal Systems Department', 'Ray and Stephanie Lane Computational Biology Department']
      JSON.parse(File.read(File.join(@source_dir, "#{key}.html"))).fetch('data').each do |person|
        departments = Array(person['dept']).map { |x| clean(x) }
        next if (departments & allowed).empty? || person['aff'] != 'Faculty'
        add('Carnegie Mellon University', person['n'], Array(person['titl']).join('; '),
            "https://www.cs.cmu.edu/directory/#{person['id']}", url(key), unit: (departments & allowed).join('; '))
      end
    end

    def gatech
      (0..12).each do |page|
        key = "gatech_scoped_#{page}"
        html(key).css('.card-block').each do |card|
          a = card.at_css('.card-block__title a')
          next unless a
          add('Georgia Institute of Technology', a.text, card.at_css('.card-block__subtitle')&.text,
              URI.join(url(key), a['href']).to_s, url(key), unit: 'SCS / IC / CSE scoped faculty filter')
        end
      end
    end

    def ucsd
      key = 'ucsd'
      html(key).css('.view-display-id-block_1 a[title][href]').uniq { |a| a['href'] }.each do |a|
        next unless a['href'].include?('/people/faculty-profiles/')
        name = a['title'].sub(/'s Profile\z/, '')
        # Filled from reviewed official engineering profiles by the enrichment step.
        add('University of California San Diego', name, nil, URI.join(url(key), a['href']).to_s, url(key), unit: 'CSE Faculty')
      end
    end

    def apply_overrides
      path = File.join(@manual, 'faculty_overrides.csv')
      return unless File.exist?(path)
      NicheRank.read_csv(path).each do |override|
        matching = @candidates.select { |r| r['university'] == override['university'] && r['name'] == override['name'] }
        raise "Override has no roster candidate: #{override['name']}" if matching.empty?
        matching.each do |r|
          r['title'] = override['title_override'] unless override['title_override'].to_s.empty?
          r['homepage_url'] = override['homepage_url_override'] unless override['homepage_url_override'].to_s.empty?
          unless override['decision'].to_s.empty?
            raise 'Invalid faculty override decision' unless %w[included excluded needs_review].include?(override['decision'])
            r['eligibility_status'] = override['decision']
            r['eligibility_reason'] = override['reason']
          end
        end
      end
    end

    def enrich_titles
      # Georgia Tech's directory truncates long titles; its profile subtitle does not.
      @candidates.select { |r| r['university'] == 'Georgia Institute of Technology' }.each do |r|
        key = "rank_georgia_#{r['homepage_url'].split('/').last}"
        next unless File.exist?(File.join(@source_dir, "#{key}.html"))
        title = html(key).at_css('.card-block__subtitle')
        next unless title && !clean(title.text).empty?
        r['title'] = clean(title.text)
        r['source_url'] = [r['source_url'], url(key)].uniq.join('; ')
      end
      # MIT's two non-paragraph title layouts need their official detail page.
      @candidates.select { |r| r['university'] == 'Massachusetts Institute of Technology' && r['title'].empty? }.each do |r|
        key = "rank_massachusetts_#{r['homepage_url'].sub(%r{/\z}, '').split('/').last}"
        next unless File.exist?(File.join(@source_dir, "#{key}.html"))
        title = html(key).css('main div').select { |n| clean(n.text).match?(/professor/i) && n.element_children.empty? }.min_by { |n| n.text.size }
        next unless title
        r['title'] = clean(title.text)
        r['source_url'] = [r['source_url'], url(key)].uniq.join('; ')
      end
      # UCSD CS cards omit ranks. Join against the official Jacobs CSE listing;
      # a reviewed name-override table handles initials and different given names.
      ranks = {}
      Dir[File.join(@source_dir, 'ucsd_jacobs_cse_*.html')].sort.each do |path|
        key = File.basename(path, '.html')
        html(key).css('.view-content .row').each do |card|
          a = card.at_css('.font-weight-bold a')
          title = card.at_css('.faculty_list_associations')
          next unless a && title
          last, first = clean(a.text).split(',', 2)
          name = first ? "#{first.strip} #{last}" : last
          title.css('br').each { |br| br.replace('; ') }
          ranks[NicheRank.normalize(name)] = { 'title' => clean(title.text), 'source_url' => url(key), 'profile_url' => URI.join(url(key), a['href']).to_s }
        end
      end
      aliases_path = File.join(@manual, 'ucsd_name_variants.csv')
      variants = File.exist?(aliases_path) ? NicheRank.read_csv(aliases_path).to_h { |r| [NicheRank.normalize(r['cs_name']), NicheRank.normalize(r['engineering_name'])] } : {}
      @candidates.select { |r| r['university'] == 'University of California San Diego' }.each do |r|
        key = NicheRank.normalize(r['name'])
        target = variants.fetch(key, key)
        rank = ranks[target] || ranks.find { |k, _| k.delete(' ') == target.delete(' ') }&.last
        next unless rank
        r['title'] = rank['title']
        r['source_url'] = [r['source_url'], rank['source_url']].join('; ')
      end
      NicheRank.write_csv(File.join(@manual, 'ucsd_rank_evidence.csv'), %w[normalized_name title source_url profile_url],
                         ranks.sort.map { |name, row| row.merge('normalized_name' => name) })
    end

    def prepare
      stanford; uiuc; mit; berkeley; uw; michigan; cornell; cmu; gatech; ucsd
      # Deduplicate repeated directory memberships; retain all unit/source evidence.
      @candidates = @candidates.group_by { |r| [r['university'], NicheRank.normalize(r['name'])] }.values.map do |rows|
        row = rows.first.dup
        row['unit'] = rows.map { |r| r['unit'] }.uniq.join('; ')
        row['source_url'] = rows.map { |r| r['source_url'] }.uniq.join('; ')
        row
      end
      enrich_titles
      apply_overrides
      @candidates.each do |r|
        next unless r['eligibility_status'].to_s.empty?
        r['eligibility_status'], r['eligibility_reason'] = self.class.classify(r['title'], school: r['university'])
      end
      @candidates.sort_by! { |r| [r['university'], NicheRank.normalize(r['name'])] }
      NicheRank.write_csv(File.join(@manual, 'faculty_candidates.csv'), ROSTER_HEADERS + EXTRA, @candidates)
      included = @candidates.select { |r| r['eligibility_status'] == 'included' }
      NicheRank.write_csv(File.join(@manual, 'faculty_raw.csv'), ROSTER_HEADERS, included)
      summary = @candidates.group_by { |r| r['university'] }.transform_values { |rows| rows.group_by { |r| r['eligibility_status'] }.transform_values(&:size) }
      NicheRank.atomic_json(File.join(@manual, 'roster_counts.json'), summary)
      puts JSON.pretty_generate(summary)
    end
  end
end

NicheRank::PublicPreparation.new.prepare if $PROGRAM_NAME == __FILE__
