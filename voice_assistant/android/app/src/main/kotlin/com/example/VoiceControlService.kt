package com.example.voice_assistant

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale

class VoiceControlService : AccessibilityService(), TextToSpeech.OnInitListener {

    private var speechRecognizer: SpeechRecognizer? = null
    private lateinit var tts: TextToSpeech
    
    private val WAKE_WORD = "jarvis"
    private var isAwake = false
    private var isListening = false
    private var pendingAction = ""
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        tts = TextToSpeech(this, this)
        mainHandler.postDelayed({ setupSpeechRecognizer() }, 1000)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts.language = Locale("hi", "IN")
        }
    }

    private fun speak(text: String) {
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
    }

    private fun setupSpeechRecognizer() {
        if (SpeechRecognizer.isRecognitionAvailable(this)) {
            speechRecognizer?.destroy()
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    isListening = false
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (!matches.isNullOrEmpty()) {
                        val spokenText = matches[0].lowercase()
                        Log.d("VoiceAssistant", "Heard: $spokenText")
                        handleVoiceCommand(spokenText)
                    }
                    restartListening(500)
                }

                override fun onError(error: Int) {
                    isListening = false
                    Log.d("VoiceAssistant", "Error Code: $error")
                    // Safe delay to prevent mic glitch loop
                    restartListening(1000)
                }

                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() { isListening = false }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            startListening()
        }
    }

    private fun startListening() {
        if (isListening) return
        mainHandler.post {
            try {
                speechRecognizer?.cancel()
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "hi-IN")
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                speechRecognizer?.startListening(intent)
                isListening = true
            } catch (e: Exception) {
                isListening = false
                e.printStackTrace()
            }
        }
    }

    private fun restartListening(delayMs: Long) {
        mainHandler.removeCallbacksAndMessages(null)
        mainHandler.postDelayed({ startListening() }, delayMs)
    }

    private fun handleVoiceCommand(text: String) {
        if (!isAwake) {
            if (text.contains(WAKE_WORD)) {
                isAwake = true
                speak("Haanji, bataiye kya karna hai?")
            }
            return
        }

        if (pendingAction == "WAITING_FOR_MESSAGE") {
            typeTextAndSend(text)
            pendingAction = ""
            isAwake = false
            return
        }

        when {
            text.contains("whatsapp kholo") || text.contains("open whatsapp") -> {
                speak("WhatsApp khol raha hoon")
                clickOnText("WhatsApp")
                isAwake = false
            }
            text.contains("message") -> {
                speak("Kya message bhejna hai boliye")
                pendingAction = "WAITING_FOR_MESSAGE"
            }
            text.contains("back") -> {
                performGlobalAction(GLOBAL_ACTION_BACK)
                isAwake = false
            }
            text.contains("home") -> {
                performGlobalAction(GLOBAL_ACTION_HOME)
                isAwake = false
            }
            else -> {
                if (clickOnText(text)) {
                    speak("Done")
                }
                isAwake = false
            }
        }
    }

    private fun clickOnText(targetText: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByText(targetText)
        if (!nodes.isNullOrEmpty()) {
            for (node in nodes) {
                if (node.isClickable) {
                    node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    return true
                } else {
                    var parent = node.parent
                    while (parent != null) {
                        if (parent.isClickable) {
                            parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            return true
                        }
                        parent = parent.parent
                    }
                }
            }
        }
        return false
    }

    private fun typeTextAndSend(textToType: String) {
        val rootNode = rootInActiveWindow ?: return
        val focusNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focusNode != null) {
            val arguments = Bundle()
            arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToType)
            focusNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
            
            mainHandler.postDelayed({
                clickOnText("Send") || clickOnText("Bhejein")
            }, 1000)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
    
    override fun onDestroy() {
        super.onDestroy()
        speechRecognizer?.destroy()
        tts.shutdown()
    }
}