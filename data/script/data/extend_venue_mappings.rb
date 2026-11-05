#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'lib/nicherank'

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  directory = File.join(root, 'db/data/manual')
  rows = NicheRank.read_csv(File.join(directory, 'venue_tiers.csv'))
  core = NicheRank.read_csv(File.join(directory, 'core2023.csv')).to_h { |r| [r['acronym'].upcase, r] }
  aliases = {
    'neural information processing systems' => 'NeurIPS',
    'CHI Conference on Human Factors in Computing Systems' => 'CHI',
    'IEEE Computer Society Conference on Computer Vision and Pattern Recognition/Proceedings - IEEE Computer Society Conference on Computer Vision and Pattern Recognition/Proceedings' => 'CVPR',
    'Proceedings - IEEE International Conference on Robotics and Automation/Proceedings' => 'ICRA',
    'Conference on Empirical Methods in Natural Language Processing (EMNLP)' => 'EMNLP',
    'Proceedings of the AAAI Conference on Artificial Intelligence' => 'AAAI',
    'Proceedings of the conference - Association for Computational Linguistics. Meeting' => 'ACL',
    'IEEE/RSJ International Conference on Intelligent Robots and Systems (IROS)' => 'IROS',
    'ACM Symposium on Theory of Computing (STOC)' => 'STOC',
    'IEEE/CVF International Conference on Computer Vision (ICCV)' => 'ICCV',
    'Conference of the North American Chapter of the Association for Computational Linguistics: Human Language Technologies (NAACL-HLT)' => 'NAACL',
    'ACM SIGKDD Conference on Knowledge Discovery and Data Mining (KDD)' => 'KDD',
    'ACM Symposium on User Interface Software and Technology (UIST)' => 'UIST',
    'Annual Symposium on Foundations of Computer Science' => 'FOCS',
    'Interspeech (USB)' => 'INTERSPEECH',
    'International World Wide Web Conference (WWW)' => 'WWW',
    'ACM SIGMOD International Conference on Management of Data (SIGMOD)' => 'SIGMOD',
    'International Conference on Architectural Support for Programming Languages and Operating Systems (ASPLOS)' => 'ASPLOS',
    'ACM/IEEE International Conference on Human-Robot Interaction (HRI)' => 'HRI',
    'ACM SIGSAC Conference on Computer and Communications Security (CCS)' => 'CCS'
  }
  aliases.each do |venue, acronym|
    reference = core.fetch(acronym.upcase)
    raise "Unranked CORE alias: #{acronym}" unless NicheRank::TIERS.include?(reference['rank'])
    rows << { 'venue' => venue, 'venue_tier' => reference['rank'], 'kind' => 'conference', 'source' => reference['source_url'],
              'notes' => "Exact OpenAlex display-name alias for CORE2023 entry #{reference['core_id']} (#{acronym}); no workshop or findings inheritance" }
  end
  {
    'ACM Transactions on Graphics' => ['A*', 'https://dl.acm.org/journal/tog'],
    'Journal of the ACM' => ['A*', 'https://dl.acm.org/journal/jacm'],
    'IEEE Transactions on Robotics' => ['A*', 'https://www.ieee-ras.org/publications/t-ro/'],
    'IEEE Transactions on Software Engineering' => ['A*', 'https://www.computer.org/csdl/journal/ts'],
    'IEEE Robotics and Automation Letters' => ['A', 'https://www.ieee-ras.org/publications/ra-l']
  }.each do |venue, (tier, source)|
    rows << { 'venue' => venue, 'venue_tier' => tier, 'kind' => 'journal_custom', 'source' => source,
              'notes' => 'NicheRank iteration-1 custom journal policy approved by backend team; project-assigned tier, not a CORE journal rating; apply only to exact venue name' }
  end
  grouped = rows.group_by { |r| NicheRank.normalize(r['venue']) }
  raise 'Conflicting mapping' if grouped.any? { |_, group| group.map { |r| r['venue_tier'] }.uniq.size > 1 }
  output = grouped.values.map(&:last).sort_by { |r| r['venue'] }
  NicheRank.write_csv(File.join(directory, 'venue_tiers.csv'), %w[venue venue_tier kind source notes], output)
  puts "#{output.size} exact venue mappings"
end
