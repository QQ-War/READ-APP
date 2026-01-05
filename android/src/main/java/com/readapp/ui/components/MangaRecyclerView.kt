package com.readapp.ui.components

import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.ImageView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import coil.request.ErrorResult
import coil.request.ImageRequest

class MangaAdapter(
    var paragraphs: List<String>,
    private val serverUrl: String,
    private val chapterUrl: String?,
    private val forceProxy: Boolean
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
            // 移除这里的点击，改为由外层 RecyclerView 统一处理，提高灵敏度
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
                listener(object : coil.request.ImageRequest.Listener {
                    override fun onError(request: ImageRequest, result: ErrorResult) {
                        if (!forceProxy && proxyUrl != null) {
                            holder.imageView.post {
                                holder.imageView.load(proxyUrl)
                            }
                        }
                    }
                })
            }
        } else {
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
            val rv = RecyclerView(context).apply {
                layoutManager = LinearLayoutManager(context)
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                adapter = MangaAdapter(paragraphs, serverUrl, chapterUrl, forceProxy)
                
                addOnScrollListener(object : RecyclerView.OnScrollListener() {
                    override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                        val firstPos = (layoutManager as LinearLayoutManager).findFirstVisibleItemPosition()
                        if (firstPos != RecyclerView.NO_POSITION) {
                            onScroll(firstPos)
                        }
                    }
                })
            }

            // 使用 GestureDetector 处理点击，确保灵敏度且不干扰滑动
            val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    val width = rv.width
                    val height = rv.height
                    // 判定中间区域：水平中间 60%，垂直中间 80%
                    if (e.x > width * 0.2 && e.x < width * 0.8 &&
                        e.y > height * 0.1 && e.y < height * 0.9) {
                        onToggleControls()
                        return true
                    }
                    return false
                }
            })

            rv.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
                override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                    gestureDetector.onTouchEvent(e)
                    return false // 不拦截，让滑动继续
                }
            })

            rv
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
