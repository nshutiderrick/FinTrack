package dev.personal.expense_tracker

import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.File
import kotlin.math.abs

/**
 * Reads a statement PDF's text on the phone, one table cell per line, in the
 * order the cells are drawn. That is the layout StatementParser expects (the
 * same as PyMuPDF's span text). Nothing leaves the phone.
 */
object PdfText {
    fun read(context: Context, path: String): String {
        PDFBoxResourceLoader.init(context.applicationContext)
        PDDocument.load(File(path)).use { doc ->
            val stripper = CellStripper()
            stripper.getText(doc)
            stripper.flush()
            return stripper.out.toString()
        }
    }

    /** Starts a new line when the text moves to another line or jumps across a wide gap. */
    private class CellStripper : PDFTextStripper() {
        val out = StringBuilder()
        private val cell = StringBuilder()
        private var started = false
        private var lastY = 0f
        private var lastEnd = 0f

        override fun processTextPosition(t: TextPosition) {
            val x = t.xDirAdj
            val y = t.yDirAdj
            val w = t.widthDirAdj
            val space = if (t.widthOfSpace > 0f) t.widthOfSpace else w
            if (started) {
                val newLine = abs(y - lastY) > t.heightDir * 0.5f
                val gap = x - lastEnd
                if (newLine || gap > space * 1.5f || gap < -space) {
                    flush()
                } else if (gap > space * 0.25f && cell.isNotEmpty() && cell.last() != ' ') {
                    cell.append(' ')
                }
            }
            cell.append(t.unicode)
            lastEnd = x + w
            lastY = y
            started = true
        }

        fun flush() {
            val s = cell.toString().trim()
            if (s.isNotEmpty()) out.append(s).append('\n')
            cell.setLength(0)
        }

        override fun endPage(page: PDPage) {
            flush()
            started = false
            super.endPage(page)
        }
    }
}
