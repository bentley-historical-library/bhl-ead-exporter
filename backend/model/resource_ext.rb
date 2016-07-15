Resource.class_eval do |variable|
	def self.id_to_eadid(id)
		res = Resource[id]
		res[:ead_id]
	end
end