package com.readapp.ui.components

import android.view.GestureDetector
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import java.io.ByteArrayOutputStream
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import coil.request.ErrorResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.readapp.data.ApiBackend
import com.readapp.data.detectApiBackend
import com.readapp.data.normalizeApiBaseUrl
import com.readapp.data.stripApiBasePath
import com.readapp.data.LocalCacheManager
import com.readapp.data.manga.MangaAntiScrapingService
import com.readapp.data.manga.MangaImageNormalizer

class MangaAdapter(
    var paragraphs: List<String>,
    private val serverUrl: String,
    private val chapterUrl: String?,
    private val forceProxy: Boolean,
    private val bookUrl: String?,
    private val chapterIndex: Int?
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
            val base = stripApiBasePath(serverUrl)
            val finalUrl = MangaImageNormalizer.resolveUrl(imgUrl, base)
            val proxyUrl = buildProxyUrl(finalUrl)
            val requestUrl = if (forceProxy && proxyUrl != null) proxyUrl else finalUrl
            val profile = MangaAntiScrapingService.resolveProfile(finalUrl, chapterUrl)
            val referer = MangaAntiScrapingService.resolveReferer(profile, chapterUrl, finalUrl)
            val cacheManager = LocalCacheManager(holder.imageView.context)
            val cachedBytes = if (!bookUrl.isNullOrBlank() && chapterIndex != null) {
                cacheManager.loadMangaImage(bookUrl, chapterIndex, finalUrl)
            } else null

            if (cachedBytes != null) {
                holder.imageView.load(cachedBytes) { crossfade(false) }
                return
            }

            holder.imageView.load(requestUrl) {
                crossfade(true)
                if (referer != null) {
                    addHeader("Referer", referer)
                }
                val ua = profile?.userAgent ?: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"
                addHeader("User-Agent", ua)
                profile?.extraHeaders?.forEach { (key, value) ->
                    addHeader(key, value)
                }
                listener(object : coil.request.ImageRequest.Listener {
                    override fun onSuccess(request: ImageRequest, result: SuccessResult) {
                        if (!bookUrl.isNullOrBlank() && chapterIndex != null) {
                            val bytes = drawableToBytes(result.drawable)
                            if (bytes != null && bytes.isNotEmpty()) {
                                cacheManager.saveMangaImage(bookUrl, chapterIndex, finalUrl, bytes)
                            }
                        }
                    }

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

    private fun buildProxyUrl(finalUrl: String): String? {
        val backend = detectApiBackend(serverUrl)
        if (backend != ApiBackend.Read) {
            return null
        }
        val base = stripApiBasePath(normalizeApiBaseUrl(serverUrl, backend))
        return android.net.Uri.parse(base).buildUpon()
            .path("api/5/proxypng")
            .appendQueryParameter("url", finalUrl)
            .appendQueryParameter("accessToken", "")
            .build()
            .toString()
    }

    private fun drawableToBytes(drawable: android.graphics.drawable.Drawable): ByteArray? {
        val bitmap = when (drawable) {
            is BitmapDrawable -> drawable.bitmap
            else -> {
                val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: return null
                val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: return null
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { canvasBitmap ->
                    val canvas = android.graphics.Canvas(canvasBitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                }
            }
        }
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
        return output.toByteArray()
    }
}

data class EdgeHint(val text: String, val isTop: Boolean)

@Composable
fun MangaNativeReader(
    paragraphs: List<String>,
    serverUrl: String,
    chapterUrl: String?,
    bookUrl: String?,
    chapterIndex: Int?,
    forceProxy: Boolean,
    pendingScrollIndex: Int?,
    mangaSwitchThreshold: Int,
    verticalDampingFactor: Float,
    mangaMaxZoom: Float,
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
    val scaleState = remember { mutableStateOf(1f) }
    
    AndroidView(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer(
                scaleX = scaleState.value,
                scaleY = scaleState.value,
            ),
        factory = { context ->
            val rv = RecyclerView(context).apply {
                layoutManager = LinearLayoutManager(context)
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                overScrollMode = View.OVER_SCROLL_ALWAYS
                adapter = MangaAdapter(paragraphs, serverUrl, chapterUrl, forceProxy, bookUrl, chapterIndex)
                
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
            val thresholdPx = mangaSwitchThreshold.toFloat() * density
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
                rv.translationY = 0f
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

            val scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    val newScale = scaleState.value * detector.scaleFactor
                    scaleState.value = newScale.coerceIn(1f, mangaMaxZoom)
                    return true
                }
            })


            rv.setOnTouchListener { _, event ->
                if (event.pointerCount >= 2) {
                    scaleGestureDetector.onTouchEvent(event)
                    // 当处于缩放状态时，重置拉动状态
                    if (pullingTop || pullingBottom) resetPullState()
                    return@setOnTouchListener true
                }
                
                gestureDetector.onTouchEvent(event)
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        pullStartY = event.y
                        pullingTop = isAtTop
                        pullingBottom = isAtBottom
                        hapticTriggered = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val rawDelta = event.y - pullStartY
                        if (!pullingTop && !pullingBottom) {
                            if (isAtTop && rawDelta > 0f) {
                                pullingTop = true
                                pullStartY = event.y
                            } else if (isAtBottom && rawDelta < 0f) {
                                pullingBottom = true
                                pullStartY = event.y
                            }
                        }

                        if (pullingTop || pullingBottom) {
                            val delta = event.y - pullStartY
                            // 应用阻尼系数
                            val dampedDelta = delta * verticalDampingFactor
                            
                            when {
                                pullingTop && delta > 0f -> {
                                    rv.translationY = dampedDelta
                                    updateHint(delta, true)
                                }
                                pullingBottom && delta < 0f -> {
                                    rv.translationY = dampedDelta
                                    updateHint(-delta, false)
                                }
                                else -> {
                                    rv.translationY = 0f
                                    updateHint(0f, true)
                                }
                            }
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        val delta = if (pullingTop) event.y - pullStartY else if (pullingBottom) pullStartY - event.y else 0f
                        val ready = delta > thresholdPx
                        val now = System.currentTimeMillis()
                        if (ready && now - lastSwitchTime > 700) {
                            updatedOnEdgeSwitch(if (pullingTop) -1 else 1)
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
