class Authorship < ApplicationRecord
  belongs_to :professor
  belongs_to :paper
end
