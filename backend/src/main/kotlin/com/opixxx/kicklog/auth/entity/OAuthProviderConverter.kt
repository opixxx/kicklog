package com.opixxx.kicklog.auth.entity

import jakarta.persistence.AttributeConverter
import jakarta.persistence.Converter

@Converter(autoApply = true)
class OAuthProviderConverter : AttributeConverter<OAuthProvider, String> {
    override fun convertToDatabaseColumn(attribute: OAuthProvider?): String? = attribute?.name?.lowercase()

    override fun convertToEntityAttribute(dbData: String?): OAuthProvider? = dbData?.uppercase()?.let(OAuthProvider::valueOf)
}
