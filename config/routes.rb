Rails.application.routes.draw do
  get '/saml/auth' => 'saml_idp#new'
  post '/saml/auth' => 'saml_idp#create'
  get '/saml/metadata' => 'saml_idp#metadata'

  #
  # Manager
  #

  namespace :manager do
    resources :procedures, only: [:index, :show] do
      post 'whitelist', on: :member
      post 'draft', on: :member
      post 'discard', on: :member
      post 'restore', on: :member
      post 'add_administrateur', on: :member
      post 'change_piece_justificative_template', on: :member
      get 'export_mail_brouillons', on: :member
    end

    resources :dossiers, only: [:index, :show] do
      post 'discard', on: :member
      post 'restore', on: :member
      post 'repasser_en_instruction', on: :member
    end

    resources :administrateurs, only: [:index, :show, :new, :create] do
      post 'reinvite', on: :member
      delete 'delete', on: :member
    end

    resources :users, only: [:index, :show, :edit, :update] do
      delete 'delete', on: :member
      post 'resend_confirmation_instructions', on: :member
      put 'enable_feature', on: :member
      get 'emails', on: :member
      put 'unblock_email'
    end

    resources :instructeurs, only: [:index, :show] do
      post 'reinvite', on: :member
      delete 'delete', on: :member
    end

    resources :dossiers, only: [:show]

    resources :demandes, only: [:index]

    resources :bill_signatures, only: [:index]

    resources :services, only: [:index, :show]

    post 'demandes/create_administrateur'
    post 'demandes/refuse_administrateur'

    authenticate :super_admin do
      mount Flipper::UI.app(-> { Flipper.instance }) => "/features", as: :flipper
      match "/delayed_job" => DelayedJobWeb, :anchor => false, :via => [:get, :post]
    end

    root to: "administrateurs#index"
  end

  #
  # Letter Opener
  #

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  #
  # Monitoring
  #

  get "/ping" => "ping#index"

  #
  # Authentication
  #

  devise_for :super_admins, skip: [:registrations], controllers: {
    sessions: 'super_admins/sessions',
    passwords: 'super_admins/passwords'
  }

  devise_scope :super_admin do
    get '/super_admins/password/test_strength' => 'super_admins/passwords#test_strength'
  end

  get 'super_admins/edit_otp', to: 'super_admins#edit_otp', as: 'edit_super_admin_otp'
  put 'super_admins/enable_otp', to: 'super_admins#enable_otp', as: 'enable_super_admin_otp'

  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations',
    confirmations: 'users/confirmations',
    passwords: 'users/passwords'
  }

  devise_scope :user do
    get '/users/no_procedure' => 'users/sessions#no_procedure'
    get 'connexion-par-jeton/:id' => 'users/sessions#sign_in_by_link', as: 'sign_in_by_link'
    get 'lien-envoye/:email' => 'users/sessions#link_sent', constraints: { email: /.*/ }, as: 'link_sent'
  end

  devise_scope :administrateur do
    get '/administrateurs/password/test_strength' => 'administrateurs/passwords#test_strength'
  end

  #
  # Main routes
  #

  root 'root#index'
  get '/administration' => 'root#administration'

  get 'users' => 'users#index'
  get 'admin' => 'admin#index'

  get '/stats' => 'stats#index'
  get '/stats/download' => 'stats#download'

  namespace :france_connect do
    get 'particulier' => 'particulier#login'
    get 'particulier/callback' => 'particulier#callback'
  end

  namespace :champs do
    get ':position/siret', to: 'siret#show', as: :siret
    get ':position/dossier_link', to: 'dossier_link#show', as: :dossier_link
    post ':position/carte', to: 'carte#show', as: :carte

    get ':champ_id/carte/features', to: 'carte#index', as: :carte_features
    post ':champ_id/carte/features', to: 'carte#create'
    post ':champ_id/carte/features/import', to: 'carte#import'
    patch ':champ_id/carte/features/:id', to: 'carte#update'
    delete ':champ_id/carte/features/:id', to: 'carte#destroy'

    post ':position/repetition', to: 'repetition#show', as: :repetition
    put 'piece_justificative/:champ_id', to: 'piece_justificative#update', as: :piece_justificative
  end

  resources :attachments, only: [:show, :destroy]

  get "patron" => "root#patron"
  get "accessibilite" => "root#accessibilite"
  get "suivi" => "root#suivi"
  post "dismiss_outdated_browser" => "root#dismiss_outdated_browser"

  get "contact", to: "support#index"
  post "contact", to: "support#create"

  get "contact-admin", to: "support#admin"

  post "webhooks/helpscout", to: "webhook#helpscout"
  match "webhooks/helpscout", to: lambda { |_| [204, {}, nil] }, via: :head

  #
  # Deprecated UI
  #

  namespace :users do
    resources :dossiers, only: [] do
      post '/carte/zones' => 'carte#zones'
      get '/carte' => 'carte#show'
      post '/carte' => 'carte#save'
      post '/repousser-expiration' => 'dossiers#extend_conservation'
    end

    # Redirection of legacy "/users/dossiers" route to "/dossiers"
    get 'dossiers', to: redirect('/dossiers')
    get 'dossiers/:id/recapitulatif', to: redirect('/dossiers/%{id}')
    get 'dossiers/invites/:id', to: redirect(path: '/invites/%{id}')

    get 'activate' => '/users/activate#new'
    patch 'activate' => '/users/activate#create'
  end

  # order matters: we don't want those routes to match /admin/procedures/:id
  get 'admin/procedures/new' => 'new_administrateur/procedures#new', as: :new_admin_procedure

  namespace :admin do
    get 'activate' => '/administrateurs/activate#new'
    patch 'activate' => '/administrateurs/activate#create'
    get 'procedures/archived', to: redirect('/admin/procedures?statut=archivees')
    get 'procedures/draft', to: redirect('/admin/procedures?statut=brouillons')

    resources :procedures, only: [:destroy] do
      collection do
        get 'new_from_existing' => 'procedures#new_from_existing', as: :new_from_existing
      end

      member do
        delete :delete_logo
        delete :delete_deliberation
        delete :delete_notice
      end

      put 'archive' => 'procedures#archive', as: :archive
      get 'publish_validate' => 'procedures#publish_validate', as: :publish_validate
      put 'clone' => 'procedures#clone', as: :clone
    end

    namespace :assigns do
      get 'show' # delete after fixed tests admin/instructeurs/show_spec without this line
    end

    resources :instructeurs, only: [:index, :create, :destroy]
  end

  resources :invites, only: [:show, :destroy] do
    collection do
      post 'dossier/:dossier_id', to: 'invites#create', as: :dossier
    end
  end

  #
  # API
  #

  authenticated :user, lambda { |user| user.administrateur_id } do
    mount GraphqlPlayground::Rails::Engine, at: "/graphql", graphql_path: "/api/v2/graphql"
  end

  namespace :api do
    namespace :v1 do
      resources :procedures, only: [:index, :show] do
        resources :dossiers, only: [:index, :show]
      end
    end

    namespace :v2 do
      post :graphql, to: "graphql#execute"
      get 'dossiers/pdf/:id', format: :pdf, to: "dossiers#pdf", as: :dossier_pdf
      get 'dossiers/geojson/:id', to: "dossiers#geojson", as: :dossier_geojson
    end
  end

  #
  # User
  #

  scope module: 'users' do
    namespace :commencer do
      get '/test/:path/dossier_vide', action: 'dossier_vide_pdf_test', as: :dossier_vide_test
      get '/test/:path', action: 'commencer_test', as: :test
      get '/:path', action: 'commencer'
      get '/:path/dossier_vide', action: 'dossier_vide_pdf', as: :dossier_vide
      get '/:path/sign_in', action: 'sign_in', as: :sign_in
      get '/:path/sign_up', action: 'sign_up', as: :sign_up
      get '/:path/france_connect', action: 'france_connect', as: :france_connect
    end

    resources :dossiers, only: [:index, :show, :new] do
      member do
        get 'identite'
        patch 'update_identite'
        get 'siret'
        post 'siret', to: 'dossiers#update_siret'
        get 'etablissement'
        get 'brouillon'
        patch 'brouillon', to: 'dossiers#update_brouillon'
        get 'modifier', to: 'dossiers#modifier'
        patch 'modifier', to: 'dossiers#update'
        get 'merci'
        get 'demande'
        get 'messagerie'
        post 'commentaire' => 'dossiers#create_commentaire'
        post 'ask_deletion'
        get 'attestation'
      end

      collection do
        get 'recherche'
      end
    end
    resource :feedback, only: [:create]
    get 'demarches' => 'demarches#index'

    get 'profil' => 'profil#show'
    post 'renew-api-token' => 'profil#renew_api_token'
    # allow refresh 'renew api token' page
    get 'renew-api-token' => redirect('/profil')
    patch 'update_email' => 'profil#update_email'
  end



  #
  # Expert
  #
  scope module: 'experts', as: 'expert' do
    get 'avis', to: 'avis#index', as: 'all_avis'

    # this redirections are ephemeral, to ensure that emails sent to experts before are still valid
    # TODO : they will be removed in September, 2020
    get 'avis/:id', to: redirect('/procedures/old/avis/%{id}')
    get 'avis/:id/sign_up/email/:email', to: redirect("/procedures/old/avis/%{id}/sign_up/email/%{email}"), constraints: { email: /.*/ }

    resources :procedures, only: [ :show], param: :procedure_id do
      member do
        resources :avis, only: [:show, :update] do
          get '', action: 'procedure', on: :collection, as: :procedure
          member do
            get 'instruction'
            get 'messagerie'
            post 'commentaire' => 'avis#create_commentaire'
            post 'avis' => 'avis#create_avis'
            patch 'revoquer'
            get 'revive'
            get 'bilans_bdf'

            get 'sign_up/email/:email' => 'avis#sign_up', constraints: { email: /.*/ }, as: 'sign_up'
            post 'sign_up/email/:email' => 'avis#create_instructeur', constraints: { email: /.*/ }
          end
        end
      end
    end
  end
  



  #
  # Instructeur
  #

  scope module: 'instructeurs', as: 'instructeur' do
    get 'avis', to: 'avis#index', as: 'all_avis'

    # this redirections are ephemeral, to ensure that emails sent to experts before are still valid
    # TODO : they will be removed in September, 2020
    get 'avis/:id', to: redirect('/procedures/old/avis/%{id}')
    get 'avis/:id/sign_up/email/:email', to: redirect("/procedures/old/avis/%{id}/sign_up/email/%{email}"), constraints: { email: /.*/ }

    resources :procedures, only: [:index, :show], param: :procedure_id do
      member do
        resources :groupes, only: [:index, :show], controller: 'groupe_instructeurs' do
          member do
            post 'add_instructeur'
            delete 'remove_instructeur'
          end
        end

        resources :avis, only: [:show, :update] do
          get '', action: 'procedure', on: :collection, as: :procedure
          member do
            get 'instruction'
            get 'messagerie'
            post 'commentaire' => 'avis#create_commentaire'
            post 'avis' => 'avis#create_avis'
            patch 'revoquer'
            get 'revive'
            get 'bilans_bdf'

            get 'sign_up/email/:email' => 'avis#sign_up', constraints: { email: /.*/ }, as: 'sign_up'
            post 'sign_up/email/:email' => 'avis#create_instructeur', constraints: { email: /.*/ }
          end
        end

        patch 'update_displayed_fields'
        get 'update_sort/:table/:column' => 'procedures#update_sort', as: 'update_sort'
        post 'add_filter'
        get 'remove_filter' => 'procedures#remove_filter', as: 'remove_filter'
        get 'download_export'
        get 'stats'
        get 'email_notifications'
        patch 'update_email_notifications'
        get 'deleted_dossiers'

        resources :dossiers, only: [:show], param: :dossier_id do
          member do
            get 'attestation'
            get 'geo_data'
            get 'apercu_attestation'
            get 'bilans_bdf'
            get 'messagerie'
            get 'annotations-privees' => 'dossiers#annotations_privees'
            get 'avis'
            get 'personnes-impliquees' => 'dossiers#personnes_impliquees'
            patch 'follow'
            patch 'unfollow'
            patch 'archive'
            patch 'unarchive'
            patch 'supprimer-dossier' => 'dossiers#delete_dossier'
            patch 'annotations' => 'dossiers#update_annotations'
            post 'commentaire' => 'dossiers#create_commentaire'
            post 'passer-en-instruction' => 'dossiers#passer_en_instruction'
            post 'repasser-en-construction' => 'dossiers#repasser_en_construction'
            post 'repasser-en-instruction' => 'dossiers#repasser_en_instruction'
            post 'terminer'
            post 'send-to-instructeurs' => 'dossiers#send_to_instructeurs'
            post 'avis' => 'dossiers#create_avis'
            get 'print' => 'dossiers#print'
            get 'telecharger_pjs' => 'dossiers#telecharger_pjs'
          end
        end
      end
    end
    get "recherche" => "recherche#index"
  end

  #
  # Administrateur
  #

  namespace :admin, module: 'new_administrateur' do
    resources :procedures, except: [:destroy] do
      member do
        get 'apercu'
        get 'champs'
        get 'annotations'
        get 'monavis'
        patch 'update_monavis'
        get 'jeton'
        patch 'update_jeton'
        put :allow_expert_review
      end

      get 'publication' => 'procedures#publication', as: :publication
      put 'publish' => 'procedures#publish', as: :publish
      get 'transfert' => 'procedures#transfert', as: :transfert
      post 'transfer' => 'procedures#transfer', as: :transfer
      get 'invited_expert_list'
      put 'update_allow_decision_access' => 'procedures#update_allow_decision_access', as: :update_allow_decision_access

      resources :mail_templates, only: [:edit, :update]

      resources :groupe_instructeurs, only: [:index, :show, :create, :update, :destroy] do
        member do
          post 'add_instructeur'
          delete 'remove_instructeur'
          get 'reaffecter_dossiers'
          post 'reaffecter'
        end

        collection do
          patch 'update_routing_criteria_name'
        end
      end

      resources :administrateurs, controller: 'procedure_administrateurs', only: [:index, :create, :destroy]

      resources :types_de_champ, only: [:create, :update, :destroy] do
        member do
          patch :move
        end
      end

      resources :mail_templates, only: [:index] do
        get 'preview', on: :member
      end

      resource :attestation_template, only: [:edit, :update, :create] do
        get 'preview', on: :member
      end
      # ADDED TO ACCESS IT FROM THE IFRAME
      get 'attestation_template/preview' => 'attestation_templates#preview'
    end

    resources :services, except: [:show] do
      collection do
        patch 'add_to_procedure'
      end
    end
  end

  if Rails.env.test?
    scope 'test/api_geo' do
      get 'regions' => 'api_geo_test#regions'
      get 'communes' => 'api_geo_test#communes'
      get 'departements' => 'api_geo_test#departements'
    end
  end

  #
  # Legacy routes
  #
  get 'demandes/new' => redirect(DEMANDE_INSCRIPTION_ADMIN_PAGE_URL)

  get 'backoffice' => redirect('/procedures')
  get 'backoffice/sign_in' => redirect('/users/sign_in')
  get 'backoffice/dossiers/procedure/:procedure_id' => redirect('/procedures/%{procedure_id}')
end
