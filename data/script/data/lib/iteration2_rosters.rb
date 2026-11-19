# frozen_string_literal: true

# Iteration 2: fifteen additional schools (CSRankings US top 25, all areas,
# 2015-2026, beyond the original ten). Parsers read saved official directory
# snapshots only. The original ten schools keep their audited classifier and
# overrides unchanged; the new schools use EXTENDED_CLASSIFIER below, which
# applies the already-confirmed scope (tenure-track or research faculty;
# clinical, teaching-track, emeritus, adjunct, visiting, courtesy, affiliate
# and joint-only appointments excluded) without a manual review queue.
module NicheRank
  class PublicPreparation
    ITERATION2_SCHOOLS = [
      'University of Maryland College Park', 'Northeastern University', 'Purdue University', 'New York University',
      'University of Texas at Austin', 'University of Wisconsin-Madison', 'Princeton University', 'University of Pennsylvania',
      'Columbia University', 'University of California Los Angeles', 'University of Southern California', 'University of Chicago',
      'University of Massachusetts Amherst', 'University of California Irvine', 'Stony Brook University'
    ].freeze

    EXCLUDED_SEGMENT = [
      [/in memoriam|deceased|\(\d{4}-\d{4}\)/, 'Memorial listing of a deceased faculty member'],
      [/emerit|retired/, 'Emeritus/retired appointment'],
      [/clinical/, 'Clinical professional/teaching-track appointment; outside tenure-track or research-faculty scope adopted for this dataset.'],
      [/teach|lecturer|practice|instruction/, 'Teaching/lecturer/practice appointment'],
      [/adjunct|visiting|visitor/, 'Adjunct or visiting appointment'],
      [/post.?doc/, 'Postdoctoral appointment'],
      [/courtesy|affiliate|affiliated|associated faculty|joint|secondary|by courtesy/, 'Courtesy/affiliate/joint-only appointment']
    ].freeze

    def self.classify_extended(title)
      t = title.to_s.downcase.strip
      return ['needs_review', 'No appointment title on directory; verify official profile'] if t.empty?
      segments = t.split(/[;|]|\s{2,}/).map(&:strip).reject { |s| s.match?(/\A[\s,.]*\z/) }
      first = segments.first.to_s
      EXCLUDED_SEGMENT.each { |re, reason| return ['excluded', reason] if first.match?(re) && first.match?(/professor|faculty|scientist|lecturer|instructor|fellow/) }
      eligible = segments.find do |s|
        s.match?(/professor|\bprof\b|research scientist|research faculty/) && EXCLUDED_SEGMENT.none? { |re, _| s.match?(re) } &&
          !s.match?(/\(courtesy|courtesy:/)
      end
      return ['included', 'Eligible professor/research-faculty title in agreed unit roster'] if eligible
      EXCLUDED_SEGMENT.each { |re, reason| return ['excluded', reason] if t.match?(re) }
      ['excluded', 'Directory title is not a tenure-track or research-faculty appointment']
    end

    def link(base, href)
      value = href.to_s.strip.split(/\s+/).first.to_s.sub(/#http:.*\z/, '')
      return base if value.empty?
      URI.join(base, value).to_s
    rescue URI::Error
      base
    end

    # Directory sections other than the core/research faculty list are kept as
    # excluded evidence rows rather than silently dropped.
    def section_of(node)
      node.xpath('preceding::*[self::h2 or self::h3 or self::h4][not(contains(@class,"media-heading"))][1]').text.strip
    end

    def add_sectioned(university, name, title, homepage, source, unit:, section:, allowed:)
      if allowed.include?(section)
        add(university, name, title, homepage, source, unit: unit)
      else
        add(university, name, title, homepage, source, unit: "#{unit}; #{section}", decision: 'excluded',
            reason: "Listed under '#{section}', outside the core/research faculty scope")
      end
    end

    def tidy_title(value)
      clean(value).split(';').map(&:strip).reject { |s| s.match?(/\A[\s,.]*\z/) }.join('; ')
    end

    def text_after_heading(node, heading)
      clean(node.text.sub(heading.text, ''))
    end

    def umd
      key = 'umd'
      html(key).css('.media-body').each do |card|
        a = card.at_css('h4.media-heading a')
        next unless a
        title = tidy_title(card.children.select(&:text?).map { |n| clean(n.text) }.reject(&:empty?).join('; '))
        add_sectioned('University of Maryland College Park', a.text, title, link(url(key), a['href']), url(key), unit: 'Computer Science',
                      section: section_of(a.parent), allowed: ['CS Faculty'])
      end
    end

    def northeastern
      keys = (1..8).map { |i| "neu_tt_#{i}" } + ['neu_research']
      keys.each do |key|
        unit = key == 'neu_research' ? 'Khoury research faculty' : 'Khoury tenured/tenure-track faculty'
        html(key).css('.standard-card__content').each do |card|
          a = card.at_css('h3.standard-card__title a')
          next unless a&.[]('href').to_s.include?('/people/')
          title = card.css('p.standard-card__titles').map { |n| clean(n.text) }.join('; ')
          add('Northeastern University', a.text, title, a['href'], url(key), unit: unit)
        end
      end
    end

    def purdue
      key = 'purdue'
      html(key).css('.people-item').each do |card|
        a = card.at_css('.people-name a') || card.at_css('.people-name')
        next unless a
        href = link(url(key), a['href'])
        add('Purdue University', a.text, card.at_css('.people-title')&.text, href, url(key), unit: 'Computer Science')
      end
    end

    def nyu
      key = 'nyu_courant'
      html(key).css('ul.people-listing li').each do |card|
        a = card.at_css('p.name a')
        next unless a
        add('New York University', a.text, card.at_css('p.title')&.text, link(url(key), a['href']), url(key), unit: 'Courant Computer Science')
      end
      key = 'nyu_tandon'
      html(key).css('.card-body').each do |card|
        a = card.at_css('h3 a')
        next unless a
        add('New York University', a.text, card.at_css('.field--name-field-title')&.text, link(url(key), a['href']), url(key),
            unit: 'Tandon Computer Science and Engineering')
      end
    end

    def utexas
      key = 'utexas'
      html(key).css('.views-row').each do |card|
        a = card.at_css('.views-field-title a')
        next unless a
        add('University of Texas at Austin', a.text, card.at_css('.views-field-field-contact-faculty-title')&.text,
            link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    def wisconsin
      key = 'wisc_core'
      JSON.parse(File.read(File.join(@source_dir, "#{key}.html"))).each do |person|
        next unless Array(person['uw_staff_type']).include?(5)
        meta = person.fetch('meta')
        add('University of Wisconsin-Madison', "#{meta['_uw_first_name']} #{meta['_uw_last_name']}", meta['_uw_title'], person['link'], url(key),
            unit: 'Computer Sciences core faculty')
      end
    end

    def princeton
      key = 'princeton'
      html(key).css('.custom_card__container.people .custom_card').each do |card|
        a = card.at_css('a.custom_card__heading-link')
        next unless a
        title = card.css('.custom_card__snippet .position, .custom_card__snippet .title').map { |n| clean(n.text) }.join('; ')
        dept = clean(card.at_css('.custom_card__snippet .department')&.text)
        title = [title, dept].reject(&:empty?).join('; ') unless dept.empty? || dept.match?(/computer science/i)
        add('Princeton University', a.text, title, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    def penn
      key = 'penn'
      html(key).css('h3.card-headline').each do |heading|
        card = heading.parent
        body = card.at_css('.body-copy')
        title = body ? body.css('strong, em').map { |n| clean(n.text) }.join('; ') : ''
        href = card.at_css('a.arrow')&.[]('href') || url(key)
        section = heading.xpath('preceding::*[self::h2 or self::h3][not(contains(@class,"card-headline"))][1]').text.strip
        add_sectioned('University of Pennsylvania', heading.text, title, href, url(key), unit: 'Computer and Information Science',
                      section: section, allowed: ['Primary Faculty'])
      end
    end

    def columbia
      key = 'columbia'
      html(key).css('.faculty-row').each do |card|
        a = card.at_css('.faculty-name a') || card.at_css('.faculty-name')
        next unless a
        last, first = clean(a.text).split(',', 2)
        name = first ? "#{first.strip} #{last.strip}" : last
        href = link(url(key), a['href'])
        add('Columbia University', name, card.at_css('.faculty-title')&.text, href, url(key), unit: 'Computer Science')
      end
    end

    def ucla
      key = 'ucla_cs'
      html(key).css('article.card').each do |card|
        a = card.at_css('h4.people-title a') || card.at_css('h4.people-title')
        next unless a
        title = clean(card.at_css('.card_description p i')&.text)
        href = a['href'] ? link('https://samueli.ucla.edu/', a['href']) : 'https://samueli.ucla.edu/search-faculty/#cs'
        add('University of California Los Angeles', a.text, title, href, 'https://samueli.ucla.edu/search-faculty/#cs', unit: 'Computer Science')
      end
    end

    def usc
      key = 'usc'
      html(key).css('a').each do |a|
        card = a.at_css('.faculty-member')
        next unless card
        heading = card.at_css('h5.resultName')
        next unless heading
        add('University of Southern California', heading.text, text_after_heading(card.at_css('.faculty-text'), heading),
            link(url(key), a['href']), url(key), unit: 'Thomas Lord Department of Computer Science')
      end
    end

    def uchicago
      key = 'uchicago'
      html(key).css('.card__content').each do |card|
        position = card.at_css('.card__position')
        heading = card.at_css('.card__title')
        next unless position && heading
        href = card.parent.at_css('a.card__url')&.[]('href')
        add('University of Chicago', heading.text, position.text, link(url(key), href), url(key), unit: 'Computer Science')
      end
    end

    def umass
      key = 'umass'
      html(key).css('.person__title').each do |heading|
        card = heading.parent
        role = card.at_css('.person__role')
        role&.css('br')&.each { |br| br.replace('; ') }
        href = card.at_css('a[href^="/people/"], a[href*="cics.umass.edu/people/"]')&.[]('href') ||
               card.parent&.at_css('a[href^="/people/"]')&.[]('href')
        add('University of Massachusetts Amherst', heading.text, role&.text, link(url(key), href), url(key),
            unit: 'Manning College of Information and Computer Sciences')
      end
    end

    def uci
      { 'uci_cs' => 'Computer Science', 'uci_informatics' => 'Informatics' }.each do |key, unit|
        html(key).css('article.item--person').each do |card|
          heading = card.at_css('.person__person-title')
          next unless heading
          href = heading.at_css('a')&.[]('href') || card.at_css('a[href*="/people/"]')&.[]('href')
          section = heading.xpath('preceding::*[self::h2 or self::h3][not(contains(@class,"person__person-title"))][1]').text.strip
          allowed = key == 'uci_cs' ? ['', 'Research Scientists and Associates'] : ['Core Faculty']
          add_sectioned('University of California Irvine', heading.text, card.at_css('.person__job-title')&.text,
                        link(url(key), href), url(key), unit: unit, section: section, allowed: allowed)
        end
      end
    end

    def stonybrook
      key = 'stonybrook'
      doc = html(key)
      labels = doc.css('.dept-faculty-directory__panel').to_h { |panel| [panel['id'], clean(doc.at_css("[aria-controls=\"#{panel['id']}\"]")&.text)] }
      doc.css('article.dept-faculty-directory__card').each do |card|
        panel = card.ancestors.find { |n| n['class'].to_s.split.include?('dept-faculty-directory__panel') }
        section = labels.fetch(panel&.[]('id'), '')
        name = card.at_css('.dept-faculty-directory__name')
        next unless name
        href = card.at_css('a.dept-faculty-directory__profile-link')&.[]('href')
        add_sectioned('Stony Brook University', name.text, card.at_css('.dept-faculty-directory__title')&.text,
                      link(url(key), href), url(key), unit: 'Computer Science', section: section, allowed: ['Core Faculty', 'Research Faculty'])
      end
    end

    def iteration2
      umd; northeastern; purdue; nyu; utexas; wisconsin; princeton; penn; columbia; ucla; usc; uchicago; umass; uci; stonybrook
    end
  end
end
