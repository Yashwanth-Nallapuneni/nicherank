class Professor < ApplicationRecord
  belongs_to :university
  has_many :authorships
  has_many :papers, through: :authorships
end
