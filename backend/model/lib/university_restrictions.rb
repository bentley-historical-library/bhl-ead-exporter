module UniversityRestrictions

  def self.university_restriction_types
		%w(CR ER PR SR)
  end
  
  def self.header_text
    "Access Restrictions for University of Michigan Records"
  end

  def self.boilerplate_intro
    "University records are public records and once fully processed are generally open to research use. Records that contain personally identifiable information will be restricted in order to protect individual privacy. Certain administrative records are restricted in accordance with university policy as outlined below. The restriction of university records is subject to compliance with applicable laws, including the Michigan Freedom of Information Act."
  end

  def self.boilerplate_contents_list
    "Restricted files are indicated in the contents list of the collection’s finding aid with a restriction note indicating the restriction type and the date of expiration."
  end

  def self.boilerplate_foia
    "For further information on the restriction policy and placing Freedom of Information Act requests for restricted material, consult the reference archivist at the Bentley Historical Library (bentley.ref@umich.edu) or the University of Michigan Freedom of Information Office website (https://foia.vpcomm.umich.edu/)."
  end

  def self.cr_restrictions
    '<emph render="bold">Patient/client records</emph> are restricted for one-hundred (100) years from the date of their creation. The terms of use for particular records older than 100 years may require the research to sign a Patient/Client Access Agreement.'
  end

  def self.er_restrictions
    '<emph render="bold">Executive records</emph>: Records generated by the university\'s executive officers, deans, directors, department heads, and their designated support staff are restricted for twenty (20) years from the date of their creation.'
  end

  def self.pr_restrictions
    '<emph render="bold">Personnel-related files</emph>, including search, review, promotion, and tenure files, are restricted for thirty (30) years from the date of their creation.'
  end

  def self.sr_restrictions
    '<emph render="bold">Student educational records</emph>: FERPA\'s protection of personally identifiable information in a student\'s education records ends at the time of a student\'s death and therefore is a matter of institutional policy.  As a courtesy to the families of recently deceased students who were enrolled at the time of death, the University generally will not release information from their education records for five years without the consent of the deceased student\'s next of kin. Eighty-five (85) years after the date the records were first created, the University will presume that the student is deceased. Thereafter the student\'s education records will be open.  Student records at the Bentley Historical Library are restricted for eighty-five (85) years, but may also be made available upon proof of the death of the student.'
  end

end