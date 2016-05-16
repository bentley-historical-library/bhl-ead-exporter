ArchivesSpace::Application.routes.draw do

  [AppConfig[:frontend_proxy_prefix], AppConfig[:frontend_prefix]].uniq.each do |prefix|

    scope prefix do
      match 'resources/:id/download_bhl_ead' => 'bhlexports#download_bhl_ead', :via => [:get]
    end
  end
end