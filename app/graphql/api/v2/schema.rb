class API::V2::Schema < GraphQL::Schema
  default_max_page_size 100
  max_complexity 300
  max_depth 15

  query Types::QueryType
  mutation Types::MutationType

  context_class API::V2::Context

  def self.id_from_object(object, type_definition, ctx)
    object.to_typed_id
  end

  def self.object_from_id(id, query_ctx)
    ApplicationRecord.record_from_typed_id(id)
  rescue => e
    raise GraphQL::ExecutionError.new(e.message, extensions: { code: :not_found })
  end

  def self.resolve_type(type, obj, ctx)
    case obj
    when Procedure
      Types::DemarcheType
    when Dossier
      Types::DossierType
    when Commentaire
      Types::MessageType
    when Instructeur, User, Expert
      Types::ProfileType
    when Individual
      Types::PersonnePhysiqueType
    when Etablissement
      Types::PersonneMoraleType
    when GroupeInstructeur
      Types::GroupeInstructeurType
    else
      raise GraphQL::ExecutionError.new("Unexpected object: #{obj}")
    end
  end

  orphan_types Types::Champs::AddressChampType,
    Types::Champs::CarteChampType,
    Types::Champs::CheckboxChampType,
    Types::Champs::CiviliteChampType,
    Types::Champs::DateChampType,
    Types::Champs::DatetimeChampType,
    Types::Champs::DecimalNumberChampType,
    Types::Champs::DossierLinkChampType,
    Types::Champs::IntegerNumberChampType,
    Types::Champs::LinkedDropDownListChampType,
    Types::Champs::MultipleDropDownListChampType,
    Types::Champs::PieceJustificativeChampType,
    Types::Champs::RepetitionChampType,
    Types::Champs::SiretChampType,
    Types::Champs::TextChampType,
    Types::Champs::TitreIdentiteChampType,
    Types::GeoAreas::ParcelleCadastraleType,
    Types::GeoAreas::SelectionUtilisateurType,
    Types::PersonneMoraleType,
    Types::PersonnePhysiqueType

  def self.unauthorized_object(error)
    # Add a top-level error to the response instead of returning nil:
    raise GraphQL::ExecutionError.new("An object of type #{error.type.graphql_name} was hidden due to permissions", extensions: { code: :unauthorized })
  end

  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
  use GraphQL::Schema::Timeout, max_seconds: 10
  use GraphQL::Batch
  use GraphQL::Backtrace

  if Rails.env.development?
    class LogQueryDepth < GraphQL::Analysis::AST::QueryDepth
      def result
        Rails.logger.info("[GraphQL Query Depth] #{super}")
      end
    end

    class LogQueryComplexity < GraphQL::Analysis::AST::QueryComplexity
      def result
        Rails.logger.info("[GraphQL Query Complexity] #{super}")
      end
    end

    query_analyzer(LogQueryComplexity)
    query_analyzer(LogQueryDepth)
  else
    query_analyzer(GraphQL::Analysis::AST::MaxQueryComplexity)
    query_analyzer(GraphQL::Analysis::AST::MaxQueryDepth)
  end
end
