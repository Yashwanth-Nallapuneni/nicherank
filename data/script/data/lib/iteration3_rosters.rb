# frozen_string_literal: true

# Iteration 3: the next batch of schools (CSRankings US, all areas, 2015-2026, ranks 26-50
# plus the four schools tied at 49). Parsers read saved official directory snapshots only
# (see db/data/manual/iteration3_sources.json). Eligibility uses the same classify_extended
# rule as iteration 2: tenure-track or research faculty; teaching, clinical, emeritus,
# adjunct, visiting, courtesy, affiliate and joint-only appointments are excluded.
# Existing schools are never touched by these parsers.
module NicheRank
  class PublicPreparation
    ITERATION3_SCHOOLS = [
      'Northwestern University', 'University of California Riverside', 'University of Virginia', 'Rutgers University',
      'University of Utah', 'Duke University', 'Pennsylvania State University', 'Texas A&M University',
      'University of California Santa Barbara', 'Boston University', 'George Mason University',
      'University of California Santa Cruz', 'Harvard University', 'Yale University', 'Arizona State University',
      'Johns Hopkins University', 'University of Illinois Chicago', 'Virginia Tech', 'North Carolina State University',
      'University of North Carolina at Chapel Hill', 'Ohio State University', 'Rice University', 'University of Colorado Boulder',
      'Brown University', 'University of California Davis', 'University at Buffalo', 'University of Minnesota'
    ].freeze

    attr_reader :candidates

    def source?(key) = File.exist?(File.join(@source_dir, "#{key}.html"))

    def nu_cs
      key = 'nu_cs'
      html(key).css('div.faculty').each do |card|
        a = card.at_css('.faculty-info h3 a')
        next unless a
        title = card.css('.faculty-info p').reject { |p| p.at_css('a.mail_link') }.map { |p| clean(p.text) }.reject(&:empty?).join('; ')
        add('Northwestern University', a.text, title, link(url(key), a['href']), url(key), unit: 'Computer Science (McCormick)')
      end
    end

    def rutgers_professors
      key = 'rutgers_professors'
      html(key).css('div.innernews').each do |card|
        a = card.at_css('h2.newstitle a')
        next unless a&.[]('href').to_s.include?('/people/professors/details/')
        card.css('script').each(&:remove)
        title = card.at_css('dl.item_details dd')&.text
        add('Rutgers University', a.text, title, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    # The page lists regular faculty first; cards that follow the "Adjunct Faculty" heading
    # (and the emeritus entries) are other appointment types and are kept as excluded evidence.
    def utah_faculty
      key = 'utah_faculty'
      section = nil
      nodes = html(key).xpath('//*[self::h2 or self::h3][not(ancestor::*[contains(@class,"t-entry")])] | //div[contains(@class,"t-inside")]')
      nodes.each do |node|
        if node.name.match?(/\Ah[23]\z/)
          section = clean(node.text) if node.text.match?(/adjunct|emerit|staff|lecturer|visiting|postdoc/i)
          next
        end
        entry = node.at_css('.t-entry')
        name = entry&.at_css('h2')
        next unless name
        site = entry.css('a').find { |a| a.text.strip == 'Website' }
        homepage = link(url(key), (site || node.at_css('a[href]'))&.[]('href'))
        title = entry.css('h4').map { |h| clean(h.text) }.reject(&:empty?).join('; ')
        if section
          add('University of Utah', name.text, title, homepage, url(key), unit: "Kahlert School of Computing; #{section}", decision: 'excluded',
              reason: "Listed under '#{section}', outside the tenure-track or research-faculty scope")
        else
          add('University of Utah', name.text, title, homepage, url(key), unit: 'Kahlert School of Computing')
        end
      end
    end

    def duke_primary
      key = 'duke_primary'
      html(key).css('article').each do |card|
        name = card.at_css('.member-card .h4')
        next unless name
        title = card.css('.h6').map { |n| clean(n.text) }.reject(&:empty?).join('; ')
        add('Duke University', name.text, title, link(url(key), card.at_css('.member-card a')&.[]('href')), url(key), unit: 'Computer Science (primary faculty)')
      end
    end

    # UC Riverside: Angular app saved from a browser. A card whose Computer Science & Engineering
    # entry is listed under "Secondary Department" is another department's faculty.
    def ucr_tenure
      key = 'ucr_tenure'
      html(key).css('app-profile-card').each do |card|
        name = card.at_css('h5')
        next unless name
        titles = card.css('.header-details li').map { |li| clean(li.text) }.reject(&:empty?)
        if clean(card.text).match?(/Secondary Department\s*Computer Science/i)
          add('University of California Riverside', name.text, titles.join('; '), nil, url(key), unit: 'Computer Science and Engineering (secondary)', decision: 'excluded',
              reason: 'Computer Science and Engineering is listed as a secondary department only')
        else
          add('University of California Riverside', name.text, titles.join('; '), nil, url(key), unit: 'Computer Science and Engineering')
        end
      end
    end

    # UVA: the list mixes CS faculty with other departments' faculty who hold a CS courtesy
    # title. Only a non-courtesy Computer Science appointment makes someone eligible.
    def uva_cs
      key = 'uva_cs'
      html(key).css('li.people_list_row').each do |row|
        a = row.at_css('.people_list_item_name a')
        next unless a
        # The directory pads names with U+FEFF; a rank and its department can be separate entries.
        name = a.text.delete("﻿")
        titles = row.css('.people_list_item_title').map { |t| clean(t.text.delete("﻿")) }.reject(&:empty?)
        own = titles.reject { |t| t.match?(/courtesy|affiliate|adjunct|visiting/i) }
        homepage = link(url(key), a['href'])
        if own.none? { |t| t.match?(/computer science/i) }
          add('University of Virginia', name, titles.join('; '), homepage, url(key), unit: 'Computer Science (other department or courtesy)', decision: 'excluded',
              reason: 'No non-courtesy Computer Science appointment listed (other department or courtesy only)')
        else
          add('University of Virginia', name, own.join('; '), homepage, url(key), unit: 'Computer Science')
        end
      end
    end

    def brown_cs
      key = 'brown_cs'
      html(key).css('li[id]').each do |card|
        name = card.at_css('> ul > li.profile-name')
        next unless name
        profile = card.css('a').find { |a| a.text.strip == 'Profile' }
        add('Brown University', name.text, card.at_css('> ul > li.profile-title')&.text, (link(url(key), profile['href']) if profile), url(key), unit: 'Computer Science')
      end
    end

    def bu_cs
      key = 'bu_cs'
      html(key).css('li.profile-item').each do |card|
        name = card.at_css('.profile-name')
        next unless name
        add('Boston University', name.text, card.at_css('.profile-title')&.text, link(url(key), card.at_css('a.profile-link')&.[]('href')), url(key), unit: 'Computer Science')
      end
    end

    # Buffalo lists tenure-line ("ladder") and teaching faculty; the title decides eligibility.
    def buf_cs
      key = 'buf_cs'
      html(key).css('div.profileinfo-teaser').each do |card|
        a = card.at_css('.profileinfo-teaser-name a.title')
        name = a&.at_css('b')&.children&.first&.text
        next if name.to_s.strip.empty?
        titles = card.css('.profileinfo-teaser-titles').map { |n| clean(n.text) }.reject(&:empty?).join('; ')
        add('University at Buffalo', name.delete(','), titles, link(url(key), a['href']), url(key), unit: 'Computer Science and Engineering')
      end
    end

    def jhu_cs
      key = 'jhu_cs'
      html(key).css('li.entity_list_item').each do |card|
        a = card.at_css('a.entity_name_link')
        next unless a
        add('Johns Hopkins University', a.text, card.at_css('.entity_title')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    def psu_cse
      key = 'psu_cse'
      html(key).css('.results-individual-revised').each do |card|
        a = card.at_css('p.name a')
        next unless a
        add('Pennsylvania State University', a.text, card.at_css('p.title')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science and Engineering')
      end
    end

    def ucsb_cs
      key = 'ucsb_cs'
      html(key).css('div.views-row').each do |card|
        a = card.at_css('h2 a')
        next unless a
        titles = card.css('p').map { |p| clean(p.text) }.select { |t| t.match?(/professor|lecturer|chair|researcher|emerit|instructor|scientist/i) }
        site = card.css('a').find { |x| x.text.match?(/website/i) }
        add('University of California Santa Barbara', a.text, titles.join('; '), link(url(key), (site || a)['href']), url(key), unit: 'Computer Science')
      end
    end

    # The Engineering school list covers every department; keep only Computer Science and Engineering.
    def ucsc_soe
      key = 'ucsc_soe'
      html(key).css('div.section-item.h-card').each do |card|
        fields = card.css('ul.item-info > li').to_h { |li| [li.at_css('strong')&.text.to_s.strip, clean(li.css('.inline-list li').map(&:text).join('; '))] }
        next unless fields['Department'].to_s.match?(/computer science and engineering/i)
        name = card.at_css('.p-name')
        next unless name
        add('University of California Santa Cruz', name.text, fields['Title'], card.at_css('a.u-url')&.[]('href'), url(key), unit: 'Computer Science and Engineering')
      end
    end

    def uic_cs
      key = 'uic_cs'
      html(key).css('article.profile-teaser').each do |card|
        a = card.at_css('._name a')
        next unless a
        last, first = clean(a.text).split(',', 2).map(&:strip)
        name = first.to_s.empty? ? last : "#{first} #{last}"
        add('University of Illinois Chicago', name, card.at_css('._academic-title')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    # Harvard's people page also lists faculty of other schools; only a Computer Science title counts.
    # A card can have no name link (only the email is linked), so the name is the text before the title.
    def harvard_cs
      %w[harvard_cs_0 harvard_cs_1 harvard_cs_2].each do |key|
        next unless source?(key)
        html(key).css('article.person-directory').each do |card|
          title = clean(card.at_css('.field-name-field-person-primary-title')&.text)
          name = clean(card.text).split(title).first.to_s.strip if !title.empty?
          link_node = card.css('a').find { |x| !x.text.strip.empty? && x.text.strip != 'More' && !x['href'].to_s.start_with?('mailto:', 'tel:') }
          name = link_node.text if link_node && (name.to_s.empty? || name.to_s.include?('@'))
          next if name.to_s.strip.empty?
          homepage = link(url(key), link_node&.[]('href'))
          if title.match?(/computer (science|engineering)/i)
            add('Harvard University', name, title, homepage, url(key), unit: 'Computer Science (SEAS)')
          else
            add('Harvard University', name, title, homepage, url(key), unit: 'Computer Science (SEAS); other school or department', decision: 'excluded',
                reason: 'No Computer Science title listed (faculty of another school or department)')
          end
        end
      end
    end

    # Minnesota's directory ends with Emeritus Faculty and In Memoriam sections.
    def umn_cs
      key = 'umn_cs'
      section = nil
      nodes = html(key).xpath('//h2 | //h3 | //div[contains(@class,"views-row")]')
      nodes.each do |node|
        if node.name.match?(/\Ah[23]\z/)
          section = clean(node.text) if node.text.match?(/emerit|memoriam|staff|adjunct|visiting/i)
          next
        end
        a = node.at_css('.people-title a')
        next unless a
        titles = node.css('.people-jobroles').map { |n| clean(n.text) }.reject(&:empty?).join('; ')
        if section
          add('University of Minnesota', a.text, titles, link(url(key), a['href']), url(key), unit: "Computer Science and Engineering; #{section}", decision: 'excluded',
              reason: "Listed under '#{section}', outside the tenure-track or research-faculty scope")
        else
          add('University of Minnesota', a.text, titles, link(url(key), a['href']), url(key), unit: 'Computer Science and Engineering')
        end
      end
    end

    def vt_cs
      key = 'vt_cs'
      html(key).css('li.bio-page').each do |card|
        a = card.at_css('a.vt-list-item-title-link')
        next unless a
        a.css('.sr-only').each(&:remove)
        add('Virginia Tech', a.text, card.at_css('.vt-list-item-description')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    # George Mason: static list in 8 pages (?page=0..7); teaching titles are excluded by the classifier.
    def gmu_cs
      (0..7).each do |page|
        key = "gmu_cs_#{page}"
        next unless source?(key)
        html(key).css('li.profile-item').each do |card|
          a = card.at_css('.view-profile-title a')
          next unless a
          titles = card.css('.view-profile-positions p').map { |p| clean(p.text) }.reject(&:empty?).join('; ')
          add('George Mason University', a.text, titles, link(url(key), a['href']), url(key), unit: 'Computer Science')
        end
      end
    end

    # UC Davis: the card lists a rank first, then departments. Only people whose departments include
    # Computer Science are eligible; other departments' faculty are kept as excluded evidence.
    def ucdavis_cs
      key = 'ucdavis_cs'
      html(key).css('article.vm-teaser').each do |card|
        a = card.at_css('h3.vm-teaser__title a')
        next unless a
        items = card.css('ul.vm-teaser__position li').map { |li| clean(li.text) }.reject(&:empty?)
        rank, departments = items.first.to_s, items.drop(1)
        homepage = link(url(key), a['href'])
        if departments.any? { |d| d.casecmp?('Computer Science') }
          add('University of California Davis', a.text, rank, homepage, url(key), unit: 'Computer Science')
        else
          add('University of California Davis', a.text, items.join('; '), homepage, url(key), unit: 'Other department', decision: 'excluded',
              reason: 'Computer Science is not among the listed departments (other department or staff)')
        end
      end
    end

    def unc_cs
      key = 'unc_cs'
      html(key).css('div.people').each do |card|
        a = card.at_css('h2 a')
        next unless a
        titles = card.css('h3').map { |h| clean(h.text) }.reject(&:empty?).join('; ')
        add('University of North Carolina at Chapel Hill', a.text, titles, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    def rice_cs
      key = 'rice_cs'
      html(key).css('div.card--bio').each do |card|
        a = card.at_css('.card__title a')
        next unless a
        add('Rice University', a.text, card.at_css('.card__title p')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science')
      end
    end

    def tamu_cs
      key = 'tamu_cs'
      html(key).css('div.profile').each do |card|
        a = card.at_css('.profile__headline a')
        next unless a
        titles = card.css('.profile__titles li').map { |li| clean(li.text) }.reject(&:empty?).join('; ')
        add('Texas A&M University', a.text, titles, link(url(key), a['href']), url(key), unit: 'Computer Science and Engineering')
      end
    end

    # Yale groups people under headings; only "Primary Faculty" is the regular faculty.
    def yale_cs
      key = 'yale_cs'
      section = nil
      html(key).xpath('//h2 | //a[contains(@class,"faculty-department-item")]').each do |node|
        if node.name == 'h2'
          section = clean(node.text)
          next
        end
        name = node.at_css('h3')&.text.to_s.strip
        next if name.empty?
        title = node.at_css('h4')&.text
        homepage = link(url(key), node['href'])
        if section == 'Primary Faculty'
          add('Yale University', name, title, homepage, url(key), unit: 'Computer Science')
        else
          add('Yale University', name, title, homepage, url(key), unit: "Computer Science; #{section}", decision: 'excluded',
              reason: "Listed under '#{section}', outside the primary tenure-track or research-faculty list")
        end
      end
    end

    # NC State: the list is split over six pages (ncsu_cs = page 1, ncsu_cs_p2..p6).
    def ncsu_cs
      (['ncsu_cs'] + (2..6).map { |n| "ncsu_cs_p#{n}" }).each do |key|
        next unless source?(key)
        html(key).css('div.person-card').each do |card|
          a = card.at_css('a.name')
          next unless a
          add('North Carolina State University', a.text, card.at_css('p.title')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science')
        end
      end
    end

    def colorado_cs
      key = 'colorado_cs'
      html(key).css('tbody.ucb-people-list-table-tablebody tr').each do |row|
        name = row.at_css('.ucb-person-card-name')
        next unless name
        add('University of Colorado Boulder', name.text, row.at_css('.ucb-person-card-title')&.text, link(url(key), row.at_css('a[href]')&.[]('href')), url(key), unit: 'Computer Science')
      end
    end

# Ohio State: 5 pages saved from a browser (osu_cs_1..osu_cs_5 = directory ?page=0..4, A-Z).
# Not run until every page is saved, so a partial list never enters the roster.
# "Last, First" names are reordered.
OSU_PAGES = (1..5).map { |n| "osu_cs_#{n}" }.freeze

    def osu_cs
      return unless OSU_PAGES.all? { |key| source?(key) }
      OSU_PAGES.each do |key|
        html(key).css('div.directory-grid-item-second-region').each do |card|
          raw = card.at_css('h2.directory-grid-name')&.text
          next if raw.to_s.strip.empty?
          last, first = clean(raw).split(',', 2).map(&:strip)
          name = first.to_s.empty? ? last : "#{first} #{last}"
          appointments = card.css('.appointment-name').map { |n| clean(n.text) }.reject(&:empty?)
          own = appointments.reject { |t| t.match?(/courtesy|affiliate|adjunct|visiting/i) }
          if own.none? { |t| t.match?(/computer science/i) }
            add('Ohio State University', name, appointments.join('; '), nil, url(key), unit: 'Computer Science and Engineering (other department or courtesy)', decision: 'excluded',
                reason: 'No non-courtesy Computer Science and Engineering appointment listed')
          else
            add('Ohio State University', name, own.join('; '), nil, url(key), unit: 'Computer Science and Engineering')
          end
        end
      end
    end

    # Arizona State: the Computer Science and Engineering discipline list of the SCAI directory
    # (5 pages, rendered by a headless browser because the list is built by JavaScript). The
    # by-rank list is not used because it also holds software and industrial engineering faculty.
    ASU_PAGES = (1..5).map { |n| "asu_cse_p#{n}" }.freeze

    def asu_cse
      return unless ASU_PAGES.all? { |key| source?(key) }
      ASU_PAGES.each do |key|
        html(key).css('div.person').each do |card|
          a = card.at_css('a.person-name')
          next unless a
          add('Arizona State University', a.text, card.at_css('.person-profession-title')&.text, link(url(key), a['href']), url(key), unit: 'Computer Science and Engineering (SCAI)')
        end
      end
    end

    ITERATION3_PARSERS = %w[nu_cs rutgers_professors utah_faculty duke_primary ucr_tenure uva_cs
                            brown_cs bu_cs buf_cs harvard_cs jhu_cs psu_cse ucsb_cs ucsc_soe uic_cs umn_cs vt_cs gmu_cs
                            ucdavis_cs unc_cs rice_cs tamu_cs yale_cs ncsu_cs colorado_cs osu_cs asu_cse].freeze

    # Runs the parser of every registered source whose snapshot exists.
    def iteration3
      # Harvard is split over several saved pages (harvard_cs_0, _1, _2).
      ITERATION3_PARSERS.each { |key| send(key) if source?(key) || (key == 'harvard_cs' && source?('harvard_cs_0')) || (key == 'gmu_cs' && source?('gmu_cs_0')) || (key == 'asu_cse' && source?('asu_cse_p1')) || (key == 'osu_cs' && source?('osu_cs_1')) }
    end
  end
end
