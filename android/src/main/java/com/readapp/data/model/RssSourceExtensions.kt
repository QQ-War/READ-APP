package com.readapp.data.model

fun RssSourceItem.toPayload(): RssSourcePayload {
    return RssSourcePayload(
        sourceUrl = sourceUrl,
        sourceName = sourceName,
        sourceIcon = sourceIcon,
        sourceGroup = sourceGroup,
        loginUrl = loginUrl,
        loginUi = loginUi,
        variableComment = variableComment,
        enabled = enabled
    )
}
