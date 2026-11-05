#!/usr/bin/env ruby
# frozen_string_literal: true
# Enrich exact venue names from the pinned CORE2023 snapshot and explicit
# project-assigned journal policy. No OpenAlex/network calls; no fuzzy matches.
require_relative 'lib/nicherank'
root=File.expand_path('../..',__dir__)
manual=File.join(root,'db/data/manual')
rows=NicheRank.read_csv(File.join(manual,'venue_tiers.csv'))
# Freeze the already-audited dedup series vocabulary: adding a tier must not
# silently change paper identity/deduplication.
frozen=File.join(manual,'dedup_series_titles.csv')
NicheRank.write_csv(frozen,['venue'],rows.map{|r|{'venue'=>r['venue']}}) unless File.exist?(frozen)
core=NicheRank.read_csv(File.join(manual,'core2023.csv'))
ranked=core.select{|r|NicheRank::TIERS.include?(r['rank'])}.group_by{|r|r['acronym'].upcase}
papers=NicheRank.read_csv(File.join(root,'data/output/full/papers.csv'))
volumes=papers.select{|p|%w[article proceedings-article].include?(p['type'])}.group_by{|p|p['venue']}.transform_values(&:size)
approved=%w[SIGCSE ISIT ASSETS CSCW CIKM ISCA SIGCOMM SIGIR PLDI HPCA MOBICOM IMC ICDE SOSP EC SPAA SC WSDM ASE IUI SENSYS SIGGRAPH SODA IPDPS PODC SIGMETRICS ASRU ICER PACT ITiCSE ICDCS RecSys LREC LAK ICTD ISPASS PODS IPSN ASONAM INFOCOM BMVC FIE MSR IJCNN ICST ITW ICCCN LICS MobileHCI SEAMS FCCM FDG].map(&:upcase)
blocked=/findings|extended abstracts|companion|system demonstrations|workshops|phd forum/i
aliases={}
volumes.each do |venue,n|
 next if n<10 || venue.to_s.match?(blocked)
 acronym=venue.to_s[/\(([^()]*)\)\s*$/,1]
 next unless acronym && approved.include?(acronym.upcase)
 candidates=ranked.fetch(acronym.upcase,[])
 next unless candidates.size==1
 aliases[venue]=acronym
end
aliases.merge!({
'Proceedings - International Symposium on Computer Architecture/Proceedings'=>'ISCA',
'IEEE Symposium on Security and Privacy (S&P)'=>'SP',
'Designing Interactive Systems Conference'=>'DIS',
'Proceedings of the International AAAI Conference on Web and Social Media'=>'ICWSM',
'IEEE Winter Conference on Applications of Computer Vision'=>'WACV',
'Design, Automation, and Test in Europe'=>'DATE',
'Network and Distributed System Security Symposium'=>'NDSS',
'ACM Joint European Software Engineering Conference and Symposium on the Foundations of Software Engineering (ESEC/FSE)'=>'FSE',
'European Conference on Computer Systems'=>'EuroSys',
'Conference of the European Chapter of the Association for Computational Linguistics'=>'EACL',
'INTERNATIONAL CONFERENCE ON MULTIMODAL INTERACTION'=>'ICMI',
'ACM SIGPLAN Symposium on Principles and Practice of Parallel Programming'=>'PPoPP',
'International Conference on Mobile Systems, Applications, and Services'=>'MobiSys',
'Proceedings of the International Conference on Automated Planning and Scheduling'=>'ICAPS',
'National Conference on Artificial Intelligence'=>'AAAI',
'SIGGRAPH Asia Conference Papers'=>'SIGGRAPH Asia',
'Conference on Innovations in Theoretical Computer Science'=>'ITCS',
'Operating Systems Design and Implementation'=>'OSDI',
'International Conference on Supercomputing'=>'ICS'
})
additions=[]
aliases.each do |venue,acronym|
 candidates=ranked.fetch(acronym.upcase,[])
 next if candidates.empty?
 raise "Ambiguous ranked acronym: #{acronym}" unless candidates.map{|r|r['rank']}.uniq.size==1
 reference=candidates.first
 additions<<{'venue'=>venue,'venue_tier'=>reference['rank'],'kind'=>'conference','source'=>reference['source_url'],
 'notes'=>"Exact reviewed display-name alias for CORE2023 entry #{reference['core_id']} (#{reference['acronym']}); not inherited by workshops, demos, companion or findings tracks"}
end
# These are project judgments permitted by the agreed high-volume flagship
# journal policy. Publisher URLs identify journals; they do NOT assert CORE tiers.
journals={
'Proceedings of the ACM on Human-Computer Interaction'=>['A','https://dl.acm.org/journal/pacmhci'],
'Proceedings of the ACM on Programming Languages'=>['A*','https://www.sigplan.org/PACMPL/'],
'Proceedings of the VLDB Endowment'=>['A*','https://www.vldb.org/pvldb/'],
'Proceedings of the ACM on Interactive Mobile Wearable and Ubiquitous Technologies'=>['A','https://dl.acm.org/journal/imwut'],
'Proceedings of the ACM on Management of Data'=>['A*','https://dl.acm.org/journal/pacmmod'],
'Proceedings of the ACM on Measurement and Analysis of Computing Systems'=>['A','https://dl.acm.org/journal/pomacs'],
'ACM Transactions on Algorithms'=>['A*','https://dl.acm.org/journal/talg'],
'ACM Transactions on Computer-Human Interaction'=>['A*','https://dl.acm.org/journal/tochi'],
'ACM Transactions on Software Engineering and Methodology'=>['A*','https://dl.acm.org/journal/tosem'],
'ACM Transactions on Knowledge Discovery from Data'=>['A','https://dl.acm.org/journal/tkdd'],
'ACM Transactions on Architecture and Code Optimization'=>['A','https://dl.acm.org/journal/taco'],
'ACM Transactions on Human-Robot Interaction'=>['A','https://dl.acm.org/journal/thri'],
'ACM Computing Surveys'=>['A*','https://dl.acm.org/journal/csur'],
'IEEE Transactions on Visualization and Computer Graphics'=>['A*','https://www.computer.org/csdl/journal/tg'],
'IEEE Transactions on Knowledge and Data Engineering'=>['A*','https://www.computer.org/csdl/journal/tk'],
'IEEE Transactions on Computers'=>['A','https://www.computer.org/csdl/journal/tc'],
'IEEE Transactions on Information Theory'=>['A*','https://www.itsoc.org/it-trans'],
'IEEE Transactions on Automatic Control'=>['A*','https://ieeecss.org/publication/transactions-automatic-control'],
'IEEE Transactions on Affective Computing'=>['A','https://www.computer.org/csdl/journal/ta'],
'International Journal of Computer Vision'=>['A*','https://link.springer.com/journal/11263'],
'The International Journal of Robotics Research'=>['A*','https://journals.sagepub.com/home/ijr'],
'Computer Graphics Forum'=>['A','https://onlinelibrary.wiley.com/journal/14678659'],
'SIAM Journal on Computing'=>['A*','https://www.siam.org/publications/journals/siam-journal-on-computing-sicomp'],
'SIAM Journal on Discrete Mathematics'=>['A','https://www.siam.org/publications/journals/siam-journal-on-discrete-mathematics-sidma'],
'SIAM Journal on Scientific Computing'=>['A','https://www.siam.org/publications/journals/siam-journal-on-scientific-computing-sisc'],
'Journal of Computational Physics'=>['A','https://www.sciencedirect.com/journal/journal-of-computational-physics'],
'Algorithmica'=>['A','https://link.springer.com/journal/453'],
'Random Structures and Algorithms'=>['A','https://onlinelibrary.wiley.com/journal/10982418'],
'Discrete & Computational Geometry'=>['A','https://link.springer.com/journal/454'],
'Mathematical Programming'=>['A*','https://link.springer.com/journal/10107'],
'Operations Research'=>['A*','https://pubsonline.informs.org/journal/opre'],
'The Annals of Statistics'=>['A*','https://imstat.org/journals-and-publications/annals-of-statistics/'],
'Journal of the American Statistical Association'=>['A*','https://www.tandfonline.com/journals/uasa20'],
'Journal of Artificial Intelligence Research'=>['A*','https://www.jair.org/'],
'Transactions of the Association for Computational Linguistics'=>['A*','https://transacl.org/'],
'Proceedings on Privacy Enhancing Technologies'=>['A','https://petsymposium.org/'],
'Nature'=>['A*','https://www.nature.com/nature/'],
'Science'=>['A*','https://www.science.org/journal/science'],
'Proceedings of the National Academy of Sciences'=>['A*','https://www.pnas.org/'],
'Nature Communications'=>['A','https://www.nature.com/ncomms/'],
'Science Advances'=>['A','https://www.science.org/journal/sciadv'],
'Nature Methods'=>['A*','https://www.nature.com/nmeth/'],
'Nature Machine Intelligence'=>['A*','https://www.nature.com/natmachintell/'],
'Nature Biotechnology'=>['A*','https://www.nature.com/nbt/'],
'Nature Genetics'=>['A*','https://www.nature.com/ng/'],
'Nature Medicine'=>['A*','https://www.nature.com/nm/'],
'Science Robotics'=>['A*','https://www.science.org/journal/scirobotics'],
'Cell'=>['A*','https://www.cell.com/cell/home'],
'Bioinformatics'=>['A','https://academic.oup.com/bioinformatics'],
'PLoS Computational Biology'=>['A','https://journals.plos.org/ploscompbiol/'],
'Genome biology'=>['A','https://genomebiology.biomedcentral.com/'],
'Nucleic Acids Research'=>['A','https://academic.oup.com/nar'],
'Journal of Computational Biology'=>['A','https://www.liebertpub.com/loi/cmb'],
'BMC Bioinformatics'=>['A','https://bmcbioinformatics.biomedcentral.com/']
}
journals.each do |venue,(tier,source)|
 next if volumes.fetch(venue,0)<20
 additions<<{'venue'=>venue,'venue_tier'=>tier,'kind'=>'journal_custom','source'=>source,
 'notes'=>"NicheRank custom flagship-journal policy, #{volumes[venue]} non-preprint article/conference records at refresh; project-assigned #{tier}, NOT a CORE journal rank. Publisher URL identifies journal only."}
end
before=rows.to_h{|r|[NicheRank.normalize(r['venue']),r]}
additions.each do |row|
 key=NicheRank.normalize(row['venue'])
 raise "Existing mapping conflict for #{row['venue']}" if before[key] && before[key]['venue_tier']!=row['venue_tier']
end
new_rows=additions.reject{|r|before.key?(NicheRank.normalize(r['venue']))}
rows=(rows+additions).group_by{|r|NicheRank.normalize(r['venue'])}.values.map(&:first).sort_by{|r|r['venue']}
NicheRank.write_csv(File.join(manual,'venue_tiers.csv'),%w[venue venue_tier kind source notes],rows)
NicheRank.write_csv(File.join(root,'reports/venues/added_mappings.csv'),%w[venue venue_tier kind source notes],new_rows)
puts "Added #{new_rows.size} exact mappings (#{new_rows.count{|r|r['kind']=='conference'}} conference, #{new_rows.count{|r|r['kind']=='journal_custom'}} custom journal); total #{rows.size}."
