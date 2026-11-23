module ApplicationHelper
  ICON_PATHS = {
    chart: "M3 13h4v8H3z M10 7h4v14h-4z M17 2h4v19h-4z",
    search: "M21 21l-5-5 M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
    bookmark: "M6 3h12v18l-6-4-6 4z",
    chevron: "M9 5l7 7-7 7",
    filters: "M3 6h5m4 0h9 M8 3v6 M3 12h11m4 0h3 M14 9v6 M3 18h5m4 0h9 M8 15v6",
    sort: "M5 3v18m-3-3 3 3 3-3 M11 5h10 M11 9h7 M11 13h4",
    globe: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M3 12h18 M12 3c-5 5-5 13 0 18 M12 3c5 5 5 13 0 18"
  }.freeze

  def ui_icon(name)
    tag.svg(tag.path(d: ICON_PATHS.fetch(name)), viewBox: "0 0 24 24", class: "icon",
            fill: "none", stroke: "currentColor", "stroke-width": 1.7,
            "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
  end

  INSTITUTION_LOGOS = {
    "I74973139" => "cmu.ico",
    "I63966007" => "mit.svg",
    "I157725225" => "illinois.svg",
    "I97018004" => "stanford.png",
    "I130701444" => "georgia-tech.ico",
    "I95457486" => "berkeley.svg",
    "I201448701" => "washington.svg",
    "I205783295" => "cornell.png",
    "I36258959" => "ucsd.ico",
    "I27837315" => "michigan.ico",
    "I66946132" => "umd.png",
    "I12912129" => "northeastern.png",
    "I219193219" => "purdue.png",
    "I57206974" => "nyu.png",
    "I86519309" => "utexas.png",
    "I135310074" => "wisc.ico",
    "I20089843" => "princeton.ico",
    "I79576946" => "upenn.ico",
    "I78577930" => "columbia.png",
    "I161318765" => "ucla.png",
    "I1174212" => "usc.png",
    "I40347166" => "uchicago.png",
    "I24603500" => "umass.png",
    "I204250578" => "uci.png",
    "I59553526" => "stonybrook.png",
    "I111979921" => "northwestern.png",
    "I103635307" => "ucr.ico",
    "I51556381" => "virginia.ico",
    "I102322142" => "rutgers.ico",
    "I223532165" => "utah.png",
    "I170897317" => "duke.png",
    "I27804330" => "brown.png",
    "I111088046" => "bu.png",
    "I63190737" => "buffalo.ico",
    "I136199984" => "harvard.png",
    "I145311948" => "jhu.png",
    "I130769515" => "psu.png",
    "I154570441" => "ucsb.png",
    "I185103710" => "ucsc.png",
    "I39422238" => "uic.png",
    "I130238516" => "umn.png",
    "I859038795" => "vt.png",
    "I162714631" => "gmu.ico",
    "I84218800" => "ucdavis.png",
    "I114027177" => "unc.png",
    "I74775410" => "rice.ico",
    "I91045830" => "tamu.png",
    "I32971472" => "yale.png",
    "I137902535" => "ncsu.svg",
    "I188538660" => "colorado.png",
    "I55732556" => "asu.ico",
    "I52357470" => "osu.svg"
  }.freeze

  def institution_logo(university)
    if (filename = INSTITUTION_LOGOS[university.openalex_id])
      return image_tag("institutions/#{filename}", class: "school-mark school-mark--logo",
                       width: 36, height: 36, alt: "", decoding: "async")
    end

    name = university.short_name.presence || university.name
    letters = name.length <= 4 ? name : name.split.map(&:first).first(3).join
    tag.span(letters, class: "school-mark school-mark--blue", "aria-hidden": true)
  end

  def ranking_navigation_params
    return @back.except(:expand) if @back
    @filters.to_params.merge(q: @query.presence, mode: @mode, sort: @sort,
                             page: @page, expand: (@expanded if @expanded.to_i.positive?)).compact
  end
end
