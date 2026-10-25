package androidx.compose.ui.geometry
data class Offset(val x: Float, val y: Float) { operator fun plus(other: Offset) = Offset(x + other.x, y + other.y); operator fun minus(other: Offset) = Offset(x - other.x, y - other.y); operator fun times(value: Float) = Offset(x * value, y * value); companion object { val Zero = Offset(0f,0f) } }
data class Size(val width: Float, val height: Float)
data class CornerRadius(val x: Float, val y: Float = x)
