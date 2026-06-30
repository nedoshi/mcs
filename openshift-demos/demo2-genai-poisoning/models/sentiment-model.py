# Simulated ML Model
import json

class SentimentModel:
    def __init__(self):
        self.version = "1.0.0"
        self.signature = None
    
    def predict(self, text):
        # Simple sentiment analysis (demo purposes)
        positive_words = ['good', 'great', 'excellent', 'happy']
        negative_words = ['bad', 'terrible', 'awful', 'sad']
        
        text_lower = text.lower()
        pos_count = sum(word in text_lower for word in positive_words)
        neg_count = sum(word in text_lower for word in negative_words)
        
        if pos_count > neg_count:
            return "POSITIVE"
        elif neg_count > pos_count:
            return "NEGATIVE"
        else:
            return "NEUTRAL"

if __name__ == "__main__":
    model = SentimentModel()
    print(json.dumps({"status": "Model loaded successfully"}))
