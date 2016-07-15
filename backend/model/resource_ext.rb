Resource.class_eval do
	def self.id_to_eadid(id)
		res = Resource[id]
		res[:ead_id]
	end
end