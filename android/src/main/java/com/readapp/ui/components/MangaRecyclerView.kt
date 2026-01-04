package com.readapp.ui.components

import android.content.Context
import android.view.ViewGroup
import android.widget.ImageView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import coil.request.ImageRequest

class MangaAdapter(
    var paragraphs: List<String>,
    private val serverUrl: String,
    private val chapterUrl: String?,
    private val forceProxy: Boolean,
    private val onToggleControls: () -> Unit
) : RecyclerView.Adapter<MangaAdapter.MangaViewHolder>() {

    class MangaViewHolder(val imageView: ImageView) : RecyclerView.ViewHolder(imageView)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MangaViewHolder {
        val imageView = ImageView(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            setOnClickListener { onToggleControls() }
        }
        return MangaViewHolder(imageView)
    }

    override fun onBindViewHolder(holder: MangaViewHolder, position: Int) {
        val text = paragraphs[position]
        val imgUrl = extractImgUrl(text)
        
        if (imgUrl != null) {
            val finalUrl = resolveUrl(imgUrl)
            val proxyUrl = buildProxyUrl(finalUrl)
            val requestUrl = if (forceProxy) proxyUrl else finalUrl
            val referer = buildReferer()

            holder.imageView.load(requestUrl) {
                crossfade(true)
                if (referer != null) {
                    addHeader("Referer", referer)
                }
                addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
                listener(onError = { _, _ ->
                    if (!forceProxy && proxyUrl != null) {
                        holder.imageView.load(proxyUrl)
                    }
                })
            }
        } else {
            // 如果不是图片，清空图片
            holder.imageView.setImageDrawable(null)
        }
    }

    override fun getItemCount(): Int = paragraphs.size

    private fun extractImgUrl(text: String): String? {
        val pattern = """(?:__IMG__|<img[^>]+(?:src|data-src)=["']?)([^"'>\s\n]+)["']?""" .toRegex()
        return pattern.find(text)?.groupValues?.get(1)
    }

    private fun resolveUrl(imgUrl: String): String {
        return if (imgUrl.startsWith("http")) imgUrl
        else {
            val base = serverUrl.replace("/api/5", "")
            if (imgUrl.startsWith("/")) "$base$imgUrl" else "$base/$imgUrl"
        }
    }

    private fun buildProxyUrl(finalUrl: String): String? {
        return android.net.Uri.parse(serverUrl).buildUpon()
            .path("api/5/proxypng")
            .appendQueryParameter("url", finalUrl)
            .appendQueryParameter("accessToken", "")
            .build().toString()
    }

    private fun buildReferer(): String? {
        return chapterUrl?.replace("http://", "https://")?.let {
            if (it.contains("kuaikanmanhua.com") && !it.endsWith("/")) "$it/" else it
        }
    }
}

@Composable
fun MangaNativeReader(
    paragraphs: List<String>,
    serverUrl: String,
    chapterUrl: String?,
    forceProxy: Boolean,
    pendingScrollIndex: Int?,
    onToggleControls: () -> Unit,
    onScroll: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            RecyclerView(context).apply {
                layoutManager = LinearLayoutManager(context)
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                adapter = MangaAdapter(paragraphs, serverUrl, chapterUrl, forceProxy, onToggleControls)
                
                addOnScrollListener(object : RecyclerView.OnScrollListener() {
                    override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                        val firstPos = (layoutManager as LinearLayoutManager).findFirstVisibleItemPosition()
                        if (firstPos != RecyclerView.NO_POSITION) {
                            onScroll(firstPos)
                        }
                    }
                })
            }
        },
        update = { recyclerView ->
            val adapter = recyclerView.adapter as MangaAdapter
            if (adapter.paragraphs != paragraphs) {
                adapter.paragraphs = paragraphs
                adapter.notifyDataSetChanged()
            }
            
            pendingScrollIndex?.let {
                (recyclerView.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(it, 0)
            }
        }
    )
}