def resolve_classification(classification_ref)
    classification_id = JSONModel::JSONModel(:classification).id_for(classification_ref)
    classification = Classification.any_repo[classification_id]
    classification_identifier = classification.identifier
    classification_identifier
end