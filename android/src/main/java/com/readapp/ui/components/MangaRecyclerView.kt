package com.readapp.ui.components

import android.view.GestureDetector
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
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

data class EdgeHint(val text: String, val isTop: Boolean)

@Composable
fun MangaNativeReader(
    paragraphs: List<String>,
    serverUrl: String,
    chapterUrl: String?,
    forceProxy: Boolean,
    pendingScrollIndex: Int?,
    onToggleControls: () -> Unit,
    onScroll: (Int) -> Unit,
    onEdgeHint: (EdgeHint?) -> Unit,
    onEdgeSwitch: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val updatedOnToggleControls by rememberUpdatedState(onToggleControls)
    val updatedOnScroll by rememberUpdatedState(onScroll)
    val updatedOnEdgeHint by rememberUpdatedState(onEdgeHint)
    val updatedOnEdgeSwitch by rememberUpdatedState(onEdgeSwitch)
    AndroidView(
        modifier = modifier,
        factory = { context ->
            val rv = RecyclerView(context).apply {
                layoutManager = LinearLayoutManager(context)
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                overScrollMode = View.OVER_SCROLL_ALWAYS
                adapter = MangaAdapter(paragraphs, serverUrl, chapterUrl, forceProxy)
                
                addOnScrollListener(object : RecyclerView.OnScrollListener() {
                    override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                        val firstPos = (layoutManager as LinearLayoutManager).findFirstVisibleItemPosition()
                        if (firstPos != RecyclerView.NO_POSITION) {
                            updatedOnScroll(firstPos)
                        }
                    }
                })
            }

            val density = context.resources.displayMetrics.density
            val hintStartPx = 24f * density
            val thresholdPx = 90f * density
            var isAtTop = true
            var isAtBottom = false
            var pullingTop = false
            var pullingBottom = false
            var pullStartY = 0f
            var lastHint: EdgeHint? = null
            var hapticTriggered = false
            var lastSwitchTime = 0L

            fun updateHint(pullDistance: Float, isTop: Boolean) {
                val absDistance = kotlin.math.abs(pullDistance)
                val hint = if (absDistance < hintStartPx) {
                    null
                } else {
                    val ready = absDistance >= thresholdPx
                    val text = when {
                        isTop && ready -> "松开切换上一章"
                        isTop -> "下拉切换上一章"
                        ready -> "松开切换下一章"
                        else -> "上拉切换下一章"
                    }
                    EdgeHint(text, isTop)
                }
                if (hint != lastHint) {
                    updatedOnEdgeHint(hint)
                    lastHint = hint
                }
                if (absDistance >= thresholdPx && !hapticTriggered) {
                    rv.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    hapticTriggered = true
                } else if (absDistance < thresholdPx && hapticTriggered) {
                    hapticTriggered = false
                }
            }

            fun resetPullState() {
                pullingTop = false
                pullingBottom = false
                pullStartY = 0f
                hapticTriggered = false
                if (lastHint != null) {
                    updatedOnEdgeHint(null)
                    lastHint = null
                }
            }

            rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    isAtTop = !recyclerView.canScrollVertically(-1)
                    isAtBottom = !recyclerView.canScrollVertically(1)
                }
            })
            rv.post {
                isAtTop = !rv.canScrollVertically(-1)
                isAtBottom = !rv.canScrollVertically(1)
            }

            // 使用 GestureDetector 处理点击，确保灵敏度且不干扰滑动
            val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    // 优化：垂直滚动模式下点击任何位置都触发菜单
                    updatedOnToggleControls()
                    return true
                }
            })

            rv.setOnTouchListener { _, event ->
                gestureDetector.onTouchEvent(event)
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        pullStartY = event.y
                        pullingTop = isAtTop
                        pullingBottom = isAtBottom
                        hapticTriggered = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        var delta = event.y - pullStartY
                        if (!pullingTop && !pullingBottom) {
                            if (isAtTop && delta > 0f) {
                                pullingTop = true
                                pullStartY = event.y
                                delta = 0f
                            } else if (isAtBottom && delta < 0f) {
                                pullingBottom = true
                                pullStartY = event.y
                                delta = 0f
                            }
                        }

                        when {
                            pullingTop && delta > 0f -> updateHint(delta, true)
                            pullingBottom && delta < 0f -> updateHint(delta, false)
                            else -> updateHint(0f, true)
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        val delta = event.y - pullStartY
                        val readyTop = pullingTop && delta > thresholdPx
                        val readyBottom = pullingBottom && delta < -thresholdPx
                        val now = System.currentTimeMillis()
                        if ((readyTop || readyBottom) && now - lastSwitchTime > 700) {
                            updatedOnEdgeSwitch(if (readyTop) -1 else 1)
                            lastSwitchTime = now
                        }
                        resetPullState()
                    }
                }
                false
            }

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
