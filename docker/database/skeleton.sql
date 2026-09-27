--
-- PostgreSQL database dump
--

\restrict dP4dIcyu4PvJGbA19Drf1qWV6GXMqMefsQK9z0oZM8CbpMaagqjPSKwW6CqqRBu

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: answer_type; Type: TYPE; Schema: public; Owner: pop_quizz_user
--

CREATE TYPE public.answer_type AS ENUM (
    'choice_label',
    'command_text',
    'text',
    'json_structure'
);


ALTER TYPE public.answer_type OWNER TO pop_quizz_user;

--
-- Name: contest_question_status; Type: TYPE; Schema: public; Owner: pop_quizz_user
--

CREATE TYPE public.contest_question_status AS ENUM (
    'waiting',
    'opened',
    'closed',
    'results'
);


ALTER TYPE public.contest_question_status OWNER TO pop_quizz_user;

--
-- Name: contest_status; Type: TYPE; Schema: public; Owner: pop_quizz_user
--

CREATE TYPE public.contest_status AS ENUM (
    'waiting',
    'running',
    'finished'
);


ALTER TYPE public.contest_status OWNER TO pop_quizz_user;

--
-- Name: question_category; Type: TYPE; Schema: public; Owner: pop_quizz_user
--

CREATE TYPE public.question_category AS ENUM (
    'culture_generale',
    'linux_command',
    'shell'
);


ALTER TYPE public.question_category OWNER TO pop_quizz_user;

--
-- Name: question_type; Type: TYPE; Schema: public; Owner: pop_quizz_user
--

CREATE TYPE public.question_type AS ENUM (
    'multiple_choice',
    'command',
    'fill_blank',
    'combination',
    'shell_code'
);


ALTER TYPE public.question_type OWNER TO pop_quizz_user;

--
-- Name: auto_close_expired_questions(); Type: FUNCTION; Schema: public; Owner: pop_quizz_user
--

CREATE FUNCTION public.auto_close_expired_questions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.contest_question cq
    SET status = 'closed'::public.contest_question_status,
        closed_at = NOW()
    FROM public.question q
    WHERE cq.question_id = q.question_id
    AND cq.status = 'opened'::public.contest_question_status
    AND cq.opened_at IS NOT NULL
    AND EXTRACT(EPOCH FROM (NOW() - cq.opened_at)) > q.duration;
END;
$$;


ALTER FUNCTION public.auto_close_expired_questions() OWNER TO pop_quizz_user;

--
-- Name: clean_expired_challenges(); Type: FUNCTION; Schema: public; Owner: pop_quizz_user
--

CREATE FUNCTION public.clean_expired_challenges() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM public.two_factor_challenge
    WHERE expires_at < NOW()
    AND validated = false;
END;
$$;


ALTER FUNCTION public.clean_expired_challenges() OWNER TO pop_quizz_user;

--
-- Name: log_answer_event(); Type: FUNCTION; Schema: public; Owner: pop_quizz_user
--

CREATE FUNCTION public.log_answer_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO public.game_event_log (contest_id, event_type, event_data)
    SELECT 
        cq.contest_id,
        'answer_submitted',
        jsonb_build_object(
            'answer_id', NEW.answer_id,
            'player_id', NEW.player_id,
            'contest_question_id', NEW.contest_question_id,
            'is_correct', NEW.is_correct,
            'earned_points', NEW.earned_points,
            'first_blood', NEW.first_blood,
            'response_time', NEW.response_time
        )
    FROM public.contest_question cq
    WHERE cq.contest_question_id = NEW.contest_question_id;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_answer_event() OWNER TO pop_quizz_user;

--
-- Name: validate_question_open(); Type: FUNCTION; Schema: public; Owner: pop_quizz_user
--

CREATE FUNCTION public.validate_question_open() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_status public.contest_question_status;
BEGIN
    SELECT status INTO v_status
    FROM public.contest_question
    WHERE contest_question_id = NEW.contest_question_id;
    
    IF v_status != 'opened'::public.contest_question_status THEN
        RAISE EXCEPTION 'Question is not open (current status: %)', v_status;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_question_open() OWNER TO pop_quizz_user;

--
-- Name: validate_timeout(); Type: FUNCTION; Schema: public; Owner: pop_quizz_user
--

CREATE FUNCTION public.validate_timeout() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_opened_at timestamp without time zone;
    v_duration integer;
BEGIN
    SELECT q.duration, cq.opened_at
    INTO v_duration, v_opened_at
    FROM public.contest_question cq
    JOIN public.question q ON cq.question_id = q.question_id
    WHERE cq.contest_question_id = NEW.contest_question_id;
    
    IF v_opened_at IS NOT NULL AND EXTRACT(EPOCH FROM (NOW() - v_opened_at)) > v_duration THEN
        RAISE EXCEPTION 'Question timeout exceeded (duration: % seconds)', v_duration;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_timeout() OWNER TO pop_quizz_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.admin (
    admin_id integer NOT NULL,
    email character varying(150) NOT NULL,
    password_hash text NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.admin OWNER TO pop_quizz_user;

--
-- Name: admin_admin_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.admin_admin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.admin_admin_id_seq OWNER TO pop_quizz_user;

--
-- Name: admin_admin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.admin_admin_id_seq OWNED BY public.admin.admin_id;


--
-- Name: answer; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.answer (
    answer_id integer NOT NULL,
    contest_question_id integer NOT NULL,
    player_id integer NOT NULL,
    answer_value jsonb NOT NULL,
    answer_type public.answer_type NOT NULL,
    is_correct boolean DEFAULT false,
    response_time numeric(10,2),
    first_blood boolean DEFAULT false,
    earned_points integer DEFAULT 0,
    submitted_at timestamp without time zone DEFAULT now(),
    CONSTRAINT answer_earned_points_positive CHECK ((earned_points >= 0)),
    CONSTRAINT answer_response_time_positive CHECK ((response_time >= (0)::numeric)),
    CONSTRAINT answer_value_valid CHECK ((((answer_type = 'choice_label'::public.answer_type) AND (jsonb_typeof(answer_value) = 'string'::text)) OR ((answer_type = 'command_text'::public.answer_type) AND (jsonb_typeof(answer_value) = 'string'::text)) OR ((answer_type = 'text'::public.answer_type) AND (jsonb_typeof(answer_value) = 'string'::text)) OR ((answer_type = 'json_structure'::public.answer_type) AND (jsonb_typeof(answer_value) = 'object'::text))))
);


ALTER TABLE public.answer OWNER TO pop_quizz_user;

--
-- Name: answer_answer_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.answer_answer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.answer_answer_id_seq OWNER TO pop_quizz_user;

--
-- Name: answer_answer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.answer_answer_id_seq OWNED BY public.answer.answer_id;


--
-- Name: contest; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.contest (
    contest_id integer NOT NULL,
    title character varying(255) NOT NULL,
    status public.contest_status DEFAULT 'waiting'::public.contest_status,
    created_by integer,
    total_questions integer DEFAULT 0,
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT contest_time_check CHECK ((((status = 'waiting'::public.contest_status) AND (start_time IS NULL) AND (end_time IS NULL)) OR ((status = 'running'::public.contest_status) AND (start_time IS NOT NULL) AND (end_time IS NULL)) OR ((status = 'finished'::public.contest_status) AND (start_time IS NOT NULL) AND (end_time IS NOT NULL) AND (end_time > start_time)))),
    CONSTRAINT contest_total_questions_positive CHECK ((total_questions >= 0))
);


ALTER TABLE public.contest OWNER TO pop_quizz_user;

--
-- Name: contest_contest_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.contest_contest_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contest_contest_id_seq OWNER TO pop_quizz_user;

--
-- Name: contest_contest_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.contest_contest_id_seq OWNED BY public.contest.contest_id;


--
-- Name: contest_player; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.contest_player (
    contest_player_id integer NOT NULL,
    contest_id integer NOT NULL,
    player_id integer NOT NULL,
    joined_at timestamp without time zone DEFAULT now(),
    is_connected boolean DEFAULT false,
    last_seen timestamp without time zone
);


ALTER TABLE public.contest_player OWNER TO pop_quizz_user;

--
-- Name: contest_player_contest_player_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.contest_player_contest_player_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contest_player_contest_player_id_seq OWNER TO pop_quizz_user;

--
-- Name: contest_player_contest_player_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.contest_player_contest_player_id_seq OWNED BY public.contest_player.contest_player_id;


--
-- Name: contest_question; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.contest_question (
    contest_question_id integer NOT NULL,
    contest_id integer NOT NULL,
    question_id integer NOT NULL,
    round_number integer NOT NULL,
    order_index integer NOT NULL,
    status public.contest_question_status DEFAULT 'waiting'::public.contest_question_status,
    opened_at timestamp without time zone,
    closed_at timestamp without time zone,
    CONSTRAINT contest_question_time_check CHECK ((((status = 'waiting'::public.contest_question_status) AND (opened_at IS NULL) AND (closed_at IS NULL)) OR ((status = 'opened'::public.contest_question_status) AND (opened_at IS NOT NULL) AND (closed_at IS NULL)) OR ((status = 'closed'::public.contest_question_status) AND (opened_at IS NOT NULL) AND (closed_at IS NOT NULL) AND (closed_at >= opened_at)) OR ((status = 'results'::public.contest_question_status) AND (opened_at IS NOT NULL) AND (closed_at IS NOT NULL))))
);


ALTER TABLE public.contest_question OWNER TO pop_quizz_user;

--
-- Name: contest_question_contest_question_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.contest_question_contest_question_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contest_question_contest_question_id_seq OWNER TO pop_quizz_user;

--
-- Name: contest_question_contest_question_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.contest_question_contest_question_id_seq OWNED BY public.contest_question.contest_question_id;


--
-- Name: contest_session; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.contest_session (
    session_id integer NOT NULL,
    contest_id integer NOT NULL,
    player_id integer NOT NULL,
    socket_id character varying(255) NOT NULL,
    connected_at timestamp without time zone DEFAULT now(),
    disconnected_at timestamp without time zone,
    CONSTRAINT session_time_check CHECK (((disconnected_at IS NULL) OR (disconnected_at >= connected_at)))
);


ALTER TABLE public.contest_session OWNER TO pop_quizz_user;

--
-- Name: contest_session_session_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.contest_session_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contest_session_session_id_seq OWNER TO pop_quizz_user;

--
-- Name: contest_session_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.contest_session_session_id_seq OWNED BY public.contest_session.session_id;


--
-- Name: game_event_log; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.game_event_log (
    event_id bigint NOT NULL,
    contest_id integer NOT NULL,
    event_type character varying(50) NOT NULL,
    event_data jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.game_event_log OWNER TO pop_quizz_user;

--
-- Name: game_event_log_event_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.game_event_log_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.game_event_log_event_id_seq OWNER TO pop_quizz_user;

--
-- Name: game_event_log_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.game_event_log_event_id_seq OWNED BY public.game_event_log.event_id;


--
-- Name: player; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.player (
    player_id integer NOT NULL,
    username character varying(100) NOT NULL,
    email character varying(150),
    password_hash text,
    avatar_url text,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT player_username_valid CHECK ((char_length((username)::text) >= 3))
);


ALTER TABLE public.player OWNER TO pop_quizz_user;

--
-- Name: player_player_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.player_player_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.player_player_id_seq OWNER TO pop_quizz_user;

--
-- Name: player_player_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.player_player_id_seq OWNED BY public.player.player_id;


--
-- Name: question; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.question (
    question_id integer NOT NULL,
    statement text NOT NULL,
    category public.question_category NOT NULL,
    type public.question_type NOT NULL,
    duration integer NOT NULL,
    points integer NOT NULL,
    explanation text,
    difficulty character varying(20) DEFAULT 'medium'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT question_duration_positive CHECK ((duration > 0)),
    CONSTRAINT question_points_positive CHECK ((points > 0))
);


ALTER TABLE public.question OWNER TO pop_quizz_user;

--
-- Name: question_choice; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.question_choice (
    choice_id integer NOT NULL,
    question_id integer NOT NULL,
    label text NOT NULL,
    content text NOT NULL,
    is_correct boolean DEFAULT false,
    order_index integer NOT NULL
);


ALTER TABLE public.question_choice OWNER TO pop_quizz_user;

--
-- Name: question_choice_choice_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.question_choice_choice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.question_choice_choice_id_seq OWNER TO pop_quizz_user;

--
-- Name: question_choice_choice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.question_choice_choice_id_seq OWNED BY public.question_choice.choice_id;


--
-- Name: question_question_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.question_question_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.question_question_id_seq OWNER TO pop_quizz_user;

--
-- Name: question_question_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.question_question_id_seq OWNED BY public.question.question_id;


--
-- Name: two_factor_challenge; Type: TABLE; Schema: public; Owner: pop_quizz_user
--

CREATE TABLE public.two_factor_challenge (
    challenge_id integer NOT NULL,
    player_id integer NOT NULL,
    command text NOT NULL,
    expected_answer text NOT NULL,
    validated boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    expires_at timestamp without time zone NOT NULL,
    CONSTRAINT challenge_expiration_check CHECK ((expires_at > created_at))
);


ALTER TABLE public.two_factor_challenge OWNER TO pop_quizz_user;

--
-- Name: two_factor_challenge_challenge_id_seq; Type: SEQUENCE; Schema: public; Owner: pop_quizz_user
--

CREATE SEQUENCE public.two_factor_challenge_challenge_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.two_factor_challenge_challenge_id_seq OWNER TO pop_quizz_user;

--
-- Name: two_factor_challenge_challenge_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pop_quizz_user
--

ALTER SEQUENCE public.two_factor_challenge_challenge_id_seq OWNED BY public.two_factor_challenge.challenge_id;


--
-- Name: v_contest_player_score; Type: VIEW; Schema: public; Owner: pop_quizz_user
--

CREATE VIEW public.v_contest_player_score AS
 SELECT cp.contest_id,
    cp.player_id,
    p.username,
    p.avatar_url,
    COALESCE(sum(a.earned_points), (0)::bigint) AS score,
    COALESCE(count(
        CASE
            WHEN a.is_correct THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS correct_answers,
    COALESCE(count(
        CASE
            WHEN (NOT a.is_correct) THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS wrong_answers,
    COALESCE(count(
        CASE
            WHEN a.first_blood THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS first_blood_count,
    COALESCE(avg(a.response_time), (0)::numeric) AS avg_response_time,
    rank() OVER (PARTITION BY cp.contest_id ORDER BY COALESCE(sum(a.earned_points), (0)::bigint) DESC, COALESCE(avg(a.response_time), (0)::numeric)) AS rank
   FROM ((public.contest_player cp
     JOIN public.player p ON ((cp.player_id = p.player_id)))
     LEFT JOIN public.answer a ON (((cp.player_id = a.player_id) AND (a.contest_question_id IN ( SELECT cq.contest_question_id
           FROM public.contest_question cq
          WHERE (cq.contest_id = cp.contest_id))))))
  GROUP BY cp.contest_id, cp.player_id, p.username, p.avatar_url;


ALTER VIEW public.v_contest_player_score OWNER TO pop_quizz_user;

--
-- Name: v_contest_question_stats; Type: VIEW; Schema: public; Owner: pop_quizz_user
--

CREATE VIEW public.v_contest_question_stats AS
 SELECT cq.contest_question_id,
    cq.contest_id,
    cq.question_id,
    cq.round_number,
    cq.order_index,
    cq.status,
    cq.opened_at,
    cq.closed_at,
    q.statement,
    q.points,
    q.duration,
    COALESCE(count(a.answer_id), (0)::bigint) AS total_answers,
    COALESCE(count(
        CASE
            WHEN a.is_correct THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS correct_answers,
    COALESCE(count(
        CASE
            WHEN a.first_blood THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS first_blood_count,
    COALESCE(avg(a.response_time), (0)::numeric) AS avg_response_time
   FROM ((public.contest_question cq
     JOIN public.question q ON ((cq.question_id = q.question_id)))
     LEFT JOIN public.answer a ON ((cq.contest_question_id = a.contest_question_id)))
  GROUP BY cq.contest_question_id, cq.contest_id, cq.question_id, cq.round_number, cq.order_index, cq.status, cq.opened_at, cq.closed_at, q.statement, q.points, q.duration;


ALTER VIEW public.v_contest_question_stats OWNER TO pop_quizz_user;

--
-- Name: v_player_score; Type: VIEW; Schema: public; Owner: pop_quizz_user
--

CREATE VIEW public.v_player_score AS
 SELECT p.player_id,
    p.username,
    p.email,
    p.avatar_url,
    COALESCE(sum(a.earned_points), (0)::bigint) AS score_total,
    COALESCE(count(
        CASE
            WHEN a.is_correct THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS total_correct,
    COALESCE(count(
        CASE
            WHEN (NOT a.is_correct) THEN 1
            ELSE NULL::integer
        END), (0)::bigint) AS total_wrong,
    COALESCE(avg(a.response_time), (0)::numeric) AS avg_response_time,
    COALESCE(count(a.answer_id), (0)::bigint) AS total_answers
   FROM (public.player p
     LEFT JOIN public.answer a ON ((p.player_id = a.player_id)))
  GROUP BY p.player_id, p.username, p.email, p.avatar_url;


ALTER VIEW public.v_player_score OWNER TO pop_quizz_user;

--
-- Name: admin admin_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.admin ALTER COLUMN admin_id SET DEFAULT nextval('public.admin_admin_id_seq'::regclass);


--
-- Name: answer answer_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.answer ALTER COLUMN answer_id SET DEFAULT nextval('public.answer_answer_id_seq'::regclass);


--
-- Name: contest contest_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest ALTER COLUMN contest_id SET DEFAULT nextval('public.contest_contest_id_seq'::regclass);


--
-- Name: contest_player contest_player_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_player ALTER COLUMN contest_player_id SET DEFAULT nextval('public.contest_player_contest_player_id_seq'::regclass);


--
-- Name: contest_question contest_question_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_question ALTER COLUMN contest_question_id SET DEFAULT nextval('public.contest_question_contest_question_id_seq'::regclass);


--
-- Name: contest_session session_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_session ALTER COLUMN session_id SET DEFAULT nextval('public.contest_session_session_id_seq'::regclass);


--
-- Name: game_event_log event_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.game_event_log ALTER COLUMN event_id SET DEFAULT nextval('public.game_event_log_event_id_seq'::regclass);


--
-- Name: player player_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.player ALTER COLUMN player_id SET DEFAULT nextval('public.player_player_id_seq'::regclass);


--
-- Name: question question_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.question ALTER COLUMN question_id SET DEFAULT nextval('public.question_question_id_seq'::regclass);


--
-- Name: question_choice choice_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.question_choice ALTER COLUMN choice_id SET DEFAULT nextval('public.question_choice_choice_id_seq'::regclass);


--
-- Name: two_factor_challenge challenge_id; Type: DEFAULT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.two_factor_challenge ALTER COLUMN challenge_id SET DEFAULT nextval('public.two_factor_challenge_challenge_id_seq'::regclass);


--
-- Data for Name: admin; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.admin (admin_id, email, password_hash, created_at) FROM stdin;
7	admin@gmail.com	$2b$10$Oi.j5dxQD9DHgxvANYKG1eITRSfQRwy5dMdCeBCQdN3T7Hw5te1l6	2026-09-02 12:06:17.979402
\.


--
-- Data for Name: answer; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.answer (answer_id, contest_question_id, player_id, answer_value, answer_type, is_correct, response_time, first_blood, earned_points, submitted_at) FROM stdin;
6	530	22	"service status nginx"	choice_label	f	19.88	f	0	2026-09-02 12:16:34.20228
7	528	22	"chown"	command_text	t	9.36	t	20	2026-09-02 12:17:30.15906
\.


--
-- Data for Name: contest; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.contest (contest_id, title, status, created_by, total_questions, start_time, end_time, created_at) FROM stdin;
28	test	running	\N	10	2026-09-02 12:10:14.711236	\N	2026-09-02 12:09:25.373158
\.


--
-- Data for Name: contest_player; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.contest_player (contest_player_id, contest_id, player_id, joined_at, is_connected, last_seen) FROM stdin;
25	28	22	2026-09-02 12:09:41.874087	t	2026-09-02 12:09:41.874087
\.


--
-- Data for Name: contest_question; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.contest_question (contest_question_id, contest_id, question_id, round_number, order_index, status, opened_at, closed_at) FROM stdin;
529	28	43	3	2	waiting	\N	\N
533	28	34	3	3	waiting	\N	\N
524	28	5	1	1	closed	2026-09-02 12:10:14.783407	2026-09-02 12:10:30.863189
525	28	1	1	2	closed	2026-09-02 12:11:23.21731	2026-09-02 12:11:39.304363
526	28	10	1	3	closed	2026-09-02 12:15:57.838261	2026-09-02 12:16:13.040498
530	28	51	1	4	closed	2026-09-02 12:16:14.329634	2026-09-02 12:16:34.20228
532	28	50	1	5	closed	2026-09-02 12:16:55.759672	2026-09-02 12:17:16.032831
528	28	27	2	1	closed	2026-09-02 12:17:20.80599	2026-09-02 12:17:30.15906
531	28	30	2	2	closed	2026-09-02 12:17:33.835186	2026-09-02 12:18:04.866206
527	28	32	3	1	closed	2026-09-02 12:18:09.262372	2026-09-02 12:18:55.333301
\.


--
-- Data for Name: contest_session; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.contest_session (session_id, contest_id, player_id, socket_id, connected_at, disconnected_at) FROM stdin;
\.


--
-- Data for Name: game_event_log; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.game_event_log (event_id, contest_id, event_type, event_data, created_at) FROM stdin;
6	28	answer_submitted	{"answer_id": 6, "player_id": 22, "is_correct": false, "first_blood": false, "earned_points": 0, "response_time": 19.88, "contest_question_id": 530}	2026-09-02 12:16:34.20228
7	28	answer_submitted	{"answer_id": 7, "player_id": 22, "is_correct": true, "first_blood": true, "earned_points": 20, "response_time": 9.36, "contest_question_id": 528}	2026-09-02 12:17:30.15906
\.


--
-- Data for Name: player; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.player (player_id, username, email, password_hash, avatar_url, created_at) FROM stdin;
1	rakoto_j	rakoto.j@etu.mg	$2b$10$dummyHashPlayer0000000000000000000001	https://api.dicebear.com/7.x/identicon/svg?seed=rakoto_j	2026-06-30 15:32:31.341266
2	hery_ravo	hery.ravo@etu.mg	$2b$10$dummyHashPlayer0000000000000000000002	https://api.dicebear.com/7.x/identicon/svg?seed=hery_ravo	2026-06-30 15:32:31.341266
3	miora_ny	miora.ny@etu.mg	$2b$10$dummyHashPlayer0000000000000000000003	https://api.dicebear.com/7.x/identicon/svg?seed=miora_ny	2026-06-30 15:32:31.341266
4	fanja21	fanja21@etu.mg	$2b$10$dummyHashPlayer0000000000000000000004	https://api.dicebear.com/7.x/identicon/svg?seed=fanja21	2026-06-30 15:32:31.341266
5	tojo_andry	tojo.andry@etu.mg	$2b$10$dummyHashPlayer0000000000000000000005	https://api.dicebear.com/7.x/identicon/svg?seed=tojo_andry	2026-06-30 15:32:31.341266
6	lova_rabe	lova.rabe@etu.mg	$2b$10$dummyHashPlayer0000000000000000000006	https://api.dicebear.com/7.x/identicon/svg?seed=lova_rabe	2026-06-30 15:32:31.341266
7	nirina_h	nirina.h@etu.mg	$2b$10$dummyHashPlayer0000000000000000000007	https://api.dicebear.com/7.x/identicon/svg?seed=nirina_h	2026-06-30 15:32:31.341266
8	zo_andriana	zo.andriana@etu.mg	$2b$10$dummyHashPlayer0000000000000000000008	https://api.dicebear.com/7.x/identicon/svg?seed=zo_andriana	2026-06-30 15:32:31.341266
9	tahiana_r	tahiana.r@etu.mg	$2b$10$dummyHashPlayer0000000000000000000009	https://api.dicebear.com/7.x/identicon/svg?seed=tahiana_r	2026-06-30 15:32:31.341266
10	faly2026	faly2026@etu.mg	$2b$10$dummyHashPlayer0000000000000000000010	https://api.dicebear.com/7.x/identicon/svg?seed=faly2026	2026-06-30 15:32:31.341266
11	hasina_m	hasina.m@etu.mg	$2b$10$dummyHashPlayer0000000000000000000011	https://api.dicebear.com/7.x/identicon/svg?seed=hasina_m	2026-06-30 15:32:31.341266
12	voahangy_t	voahangy.t@etu.mg	$2b$10$dummyHashPlayer0000000000000000000012	https://api.dicebear.com/7.x/identicon/svg?seed=voahangy_t	2026-06-30 15:32:31.341266
13	ny_aina	ny.aina@etu.mg	$2b$10$dummyHashPlayer0000000000000000000013	https://api.dicebear.com/7.x/identicon/svg?seed=ny_aina	2026-06-30 15:32:31.341266
14	mialy_rasoa	mialy.rasoa@etu.mg	$2b$10$dummyHashPlayer0000000000000000000014	https://api.dicebear.com/7.x/identicon/svg?seed=mialy_rasoa	2026-06-30 15:32:31.341266
15	tiana_r	tiana.r@etu.mg	$2b$10$dummyHashPlayer0000000000000000000015	https://api.dicebear.com/7.x/identicon/svg?seed=tiana_r	2026-06-30 15:32:31.341266
16	fenitra_k	fenitra.k@etu.mg	$2b$10$dummyHashPlayer0000000000000000000016	https://api.dicebear.com/7.x/identicon/svg?seed=fenitra_k	2026-06-30 15:32:31.341266
17	andry_be	andry.be@etu.mg	$2b$10$dummyHashPlayer0000000000000000000017	https://api.dicebear.com/7.x/identicon/svg?seed=andry_be	2026-06-30 15:32:31.341266
18	soa_rakoto	soa.rakoto@etu.mg	$2b$10$dummyHashPlayer0000000000000000000018	https://api.dicebear.com/7.x/identicon/svg?seed=soa_rakoto	2026-06-30 15:32:31.341266
19	testeur	testeur@gmail.com	$2b$10$UORhiW2kEpdr9ILrNxGQje9m08RgD1BMFLFEZTKT4DOnwo/.KDw1G	\N	2026-07-28 21:31:24.26427
20	testeur2	testeur2@gmail.com	$2b$10$WN7YKbbdsJvmPLzoF/Dw7eOA1wtSC8ZVeAlVjqVnZ4PAG8ZGs6/He	\N	2026-07-29 00:36:55.588343
21	claudine	hanitraclaudine@gmail.com	$2b$10$94VHFc7/NiKWzOiXxGhxaumKqmyDG8w6lHT7hwhi1KuxZ4F8nlOSu	https://api.dicebear.com/10.x/bottts/svg?seed=Nova	2026-07-29 18:39:21.399911
22	Cloudy	hanit@gmail.com	$2b$10$RneQrFM0IIHzfNmvQxvVsOBz2CVmMaoyEsXrGK99lTgT0JOUx9GTi	https://api.dicebear.com/10.x/bottts/svg?seed=Felix	2026-09-02 11:54:01.489477
\.


--
-- Data for Name: question; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.question (question_id, statement, category, type, duration, points, explanation, difficulty, created_at) FROM stdin;
1	Qui est le créateur original du noyau Linux ?	culture_generale	multiple_choice	15	10	Linus Torvalds a créé le noyau Linux en 1991 alors qu'il était étudiant en Finlande.	easy	2026-06-30 15:32:31.341266
2	En quelle année la première version du noyau Linux a-t-elle été publiée ?	culture_generale	multiple_choice	15	10	Linus Torvalds a annoncé Linux pour la première fois en 1991.	easy	2026-06-30 15:32:31.341266
3	Que signifie l'acronyme GNU ?	culture_generale	multiple_choice	15	10	GNU est un acronyme récursif qui se définit lui-même.	easy	2026-06-30 15:32:31.341266
4	Sous quelle licence le noyau Linux est-il principalement distribué ?	culture_generale	multiple_choice	15	10	Le noyau Linux est distribué sous licence GPL version 2.	easy	2026-06-30 15:32:31.341266
5	Quel est le nom de la mascotte officielle de Linux ?	culture_generale	multiple_choice	15	10	Tux le pingouin est la mascotte officielle du noyau Linux depuis 1996.	easy	2026-06-30 15:32:31.341266
6	Quel système d'exploitation des années 1960-1970 a fortement inspiré la création d'Unix ?	culture_generale	multiple_choice	15	10	Multics, un système d'exploitation expérimental, a directement inspiré la conception d'Unix.	easy	2026-06-30 15:32:31.341266
7	Quelle entreprise développe macOS, un système d'exploitation basé sur Unix ?	culture_generale	multiple_choice	15	10	macOS, développé par Apple, repose sur une base Unix certifiée (Darwin).	easy	2026-06-30 15:32:31.341266
8	Qui a fondé le projet de distribution Debian en 1993 ?	culture_generale	multiple_choice	15	10	Ian Murdock a fondé Debian en 1993, le nom étant une contraction de son prénom et de celui de sa compagne Deborah.	easy	2026-06-30 15:32:31.341266
9	Quelle distribution Linux d'entreprise utilise un chapeau rouge comme symbole de marque ?	culture_generale	multiple_choice	15	10	Red Hat est connue pour son logo en forme de chapeau rouge et ses solutions Linux destinées aux entreprises.	easy	2026-06-30 15:32:31.341266
10	Que signifie le sigle FOSS dans le monde du logiciel libre ?	culture_generale	multiple_choice	15	10	FOSS signifie Free and Open Source Software, regroupant logiciels libres et open source.	easy	2026-06-30 15:32:31.341266
11	Quelle commande affiche le chemin du répertoire de travail courant ?	linux_command	multiple_choice	15	10	pwd signifie print working directory.	easy	2026-06-30 15:32:31.341266
12	Quelle commande permet de lister le contenu d'un répertoire ?	linux_command	multiple_choice	15	10	ls affiche la liste des fichiers et dossiers d'un répertoire.	easy	2026-06-30 15:32:31.341266
13	Quelle commande permet de se déplacer dans l'arborescence des répertoires ?	linux_command	multiple_choice	15	10	cd signifie change directory.	easy	2026-06-30 15:32:31.341266
14	Quelle commande affiche le contenu d'un fichier texte sur la sortie standard ?	linux_command	multiple_choice	15	10	cat concatène et affiche le contenu d'un ou plusieurs fichiers.	easy	2026-06-30 15:32:31.341266
15	Quelle commande permet de copier un fichier ?	linux_command	multiple_choice	15	10	cp copie un fichier ou un répertoire vers une nouvelle destination.	easy	2026-06-30 15:32:31.341266
16	Quelle commande permet de déplacer ou de renommer un fichier ?	linux_command	multiple_choice	15	10	mv déplace un fichier, ou le renomme s'il reste dans le même répertoire.	easy	2026-06-30 15:32:31.341266
17	Quelle commande supprime un fichier ?	linux_command	multiple_choice	15	10	rm supprime définitivement un fichier (à utiliser avec précaution).	easy	2026-06-30 15:32:31.341266
18	Quelle commande crée un nouveau répertoire ?	linux_command	multiple_choice	15	10	mkdir signifie make directory.	easy	2026-06-30 15:32:31.341266
19	Quelle commande affiche la liste des processus en cours d'exécution ?	linux_command	multiple_choice	15	10	ps affiche un instantané des processus actifs.	easy	2026-06-30 15:32:31.341266
20	Quelle commande permet de modifier les permissions d'un fichier ?	linux_command	multiple_choice	15	10	chmod signifie change mode et modifie les droits d'accès.	easy	2026-06-30 15:32:31.341266
21	Quelle commande affiche la date et l'heure actuelles du système ?	linux_command	command	30	15	La commande date affiche la date et l'heure système.	medium	2026-06-30 15:32:31.341266
22	Quelle commande affiche l'espace disque utilisé et disponible sur les systèmes de fichiers ?	linux_command	command	30	15	df (disk free) affiche l'utilisation de l'espace disque.	medium	2026-06-30 15:32:31.341266
23	Quelle commande affiche la mémoire RAM utilisée et disponible ?	linux_command	command	30	15	free affiche l'état de la mémoire vive et du swap.	medium	2026-06-30 15:32:31.341266
24	Quelle commande permet de rechercher un motif texte à l'intérieur d'un fichier ?	linux_command	command	30	15	grep recherche des lignes correspondant à un motif dans un fichier.	medium	2026-06-30 15:32:31.341266
25	Quelle commande affiche les 10 premières lignes d'un fichier ?	linux_command	command	30	15	head affiche par défaut les 10 premières lignes d'un fichier.	medium	2026-06-30 15:32:31.341266
26	Quelle commande affiche les 10 dernières lignes d'un fichier ?	linux_command	command	30	15	tail affiche par défaut les 10 dernières lignes d'un fichier.	medium	2026-06-30 15:32:31.341266
27	Quelle commande change le propriétaire d'un fichier ?	linux_command	command	30	15	chown modifie le propriétaire (et éventuellement le groupe) d'un fichier.	medium	2026-06-30 15:32:31.341266
28	Quelle commande affiche le nom de l'utilisateur actuellement connecté ?	linux_command	command	30	15	whoami affiche le nom de l'utilisateur courant.	medium	2026-06-30 15:32:31.341266
29	Quelle commande crée une archive compressée nommée backup.tar.gz à partir du répertoire /data ?	linux_command	command	30	15	tar -czf crée (c), compresse en gzip (z) et nomme (f) l'archive.	medium	2026-06-30 15:32:31.341266
30	Quelle commande affiche le manuel de la commande ls ?	linux_command	command	30	15	man affiche le manuel détaillé d'une commande.	medium	2026-06-30 15:32:31.341266
31	Quelle commande liste les fichiers du répertoire courant triés par ordre alphabétique en utilisant un pipe ?	linux_command	combination	45	20	Le pipe (|) transmet la sortie de ls à la commande sort.	hard	2026-06-30 15:32:31.341266
32	Quelle commande permet de compter le nombre de fichiers dans le répertoire courant ?	linux_command	combination	45	20	wc -l compte le nombre de lignes reçues, ici une ligne par fichier listé.	hard	2026-06-30 15:32:31.341266
33	Quelle commande affiche uniquement les processus dont le nom contient 'ssh' ?	linux_command	combination	45	20	ps aux liste tous les processus, grep filtre ceux contenant ssh.	hard	2026-06-30 15:32:31.341266
34	Quelle commande affiche les 5 plus gros fichiers ou dossiers du répertoire courant ?	linux_command	combination	45	20	du -ah liste les tailles, sort -rh trie du plus gros au plus petit, head -5 garde les 5 premiers.	hard	2026-06-30 15:32:31.341266
35	Quelle commande affiche le nombre de lignes contenant le mot 'ERROR' dans le fichier access.log ?	linux_command	combination	45	20	grep filtre les lignes contenant ERROR, wc -l compte ces lignes.	hard	2026-06-30 15:32:31.341266
36	Complétez la commande pour lister tous les fichiers, y compris les fichiers cachés, avec les détails : ___ -la	linux_command	fill_blank	20	15	ls -la affiche tous les fichiers (y compris cachés) avec les détails.	medium	2026-06-30 15:32:31.341266
37	Complétez la commande pour copier récursivement le dossier projet vers backup : cp ___ projet backup	linux_command	fill_blank	20	15	L'option -r (récursive) permet de copier un dossier et tout son contenu.	medium	2026-06-30 15:32:31.341266
38	Complétez la commande pour rendre un script exécutable : chmod ___ script.sh	linux_command	fill_blank	20	15	chmod +x ajoute le droit d'exécution au fichier.	medium	2026-06-30 15:32:31.341266
39	Complétez la commande pour trouver les fichiers .log modifiés il y a moins d'un jour dans /var : find /var -name '*.log' ___ -1	linux_command	fill_blank	20	15	L'option -mtime -1 sélectionne les fichiers modifiés il y a moins d'un jour.	medium	2026-06-30 15:32:31.341266
40	Complétez la commande pour rediriger la sortie d'erreur d'un programme vers le fichier erreurs.txt : commande 2___ erreurs.txt	linux_command	fill_blank	20	15	Le descripteur 2 représente la sortie d'erreur (stderr), et > redirige vers un fichier.	medium	2026-06-30 15:32:31.341266
41	Écrivez un script shell qui affiche les nombres de 1 à 10, un par ligne.	shell	shell_code	120	30	Une boucle for parcourt la séquence {1..10} et affiche chaque valeur avec echo.	hard	2026-06-30 15:32:31.341266
42	Écrivez un script shell qui demande le nom de l'utilisateur et affiche un message de bienvenue personnalisé.	shell	shell_code	120	30	read récupère la saisie de l'utilisateur dans une variable, puis echo l'affiche dans un message.	hard	2026-06-30 15:32:31.341266
43	Écrivez un script shell qui vérifie si le fichier config.txt existe dans le répertoire courant et affiche Trouve ou Absent selon le cas.	shell	shell_code	120	30	Le test -f vérifie l'existence d'un fichier régulier ; if/else affiche le résultat correspondant.	hard	2026-06-30 15:32:31.341266
44	Quel est le créateur de Linux ?	culture_generale	multiple_choice	30	10	Linux a été créé par Linus Torvalds en 1991.	easy	2026-07-27 20:19:02.791354
45	Quel protocole est utilisé pour naviguer sur le Web ?	culture_generale	multiple_choice	30	10	HTTP est le protocole de base du Web.	easy	2026-07-27 20:19:02.791354
46	Que signifie CPU ?	culture_generale	multiple_choice	30	10	Central Processing Unit.	easy	2026-07-27 20:19:02.791354
47	Quelle entreprise développe Git ?	culture_generale	multiple_choice	30	10	Git a été créé par Linus Torvalds mais est aujourd'hui développé par la communauté.	medium	2026-07-27 20:19:02.791354
48	Quel langage est principalement utilisé pour le noyau Linux ?	culture_generale	multiple_choice	40	15	Le noyau Linux est majoritairement écrit en C.	medium	2026-07-27 20:19:02.791354
49	Quel port est utilisé par défaut pour HTTPS ?	culture_generale	multiple_choice	30	10	HTTPS utilise le port 443.	easy	2026-07-27 20:19:02.791354
50	Quelle commande affiche le répertoire courant ?	culture_generale	multiple_choice	20	10	pwd signifie print working directory.	easy	2026-07-27 20:19:02.791354
51	Quel système de contrôle de version est le plus utilisé ?	culture_generale	multiple_choice	30	10	Git est aujourd'hui le plus populaire.	easy	2026-07-27 20:19:02.791354
52	Quelle commande affiche le contenu d'un fichier texte ?	culture_generale	multiple_choice	30	10	cat affiche le contenu du fichier.	easy	2026-07-27 20:19:02.791354
53	Quel est le rôle principal d'un système d'exploitation ?	culture_generale	multiple_choice	40	15	Il gère les ressources matérielles et logicielles.	medium	2026-07-27 20:19:02.791354
54	Lister les fichiers du répertoire courant.	linux_command	command	30	15	La commande ls permet de lister les fichiers.	easy	2026-07-27 20:19:02.791354
55	Afficher le chemin absolu du dossier courant.	linux_command	command	30	15	Utiliser pwd.	easy	2026-07-27 20:19:02.791354
56	Créer un dossier nommé test.	linux_command	command	30	15	Utiliser mkdir.	easy	2026-07-27 20:19:02.791354
57	Supprimer un fichier nommé notes.txt.	linux_command	command	30	15	Utiliser rm.	easy	2026-07-27 20:19:02.791354
58	Déplacer fichier.txt vers le dossier archive.	linux_command	command	40	20	Utiliser mv.	medium	2026-07-27 20:19:02.791354
59	Copier image.png vers backup/.	linux_command	command	40	20	Utiliser cp.	medium	2026-07-27 20:19:02.791354
60	Rechercher tous les fichiers .log.	linux_command	command	45	25	La commande find est adaptée.	medium	2026-07-27 20:19:02.791354
61	Afficher les 20 dernières lignes d'un fichier.	linux_command	command	40	20	Utiliser tail.	medium	2026-07-27 20:19:02.791354
62	Donner les droits d'exécution au propriétaire.	linux_command	command	45	25	Utiliser chmod.	medium	2026-07-27 20:19:02.791354
63	Compresser un dossier projet en archive tar.gz.	linux_command	command	60	30	Utiliser tar avec gzip.	hard	2026-07-27 20:19:02.791354
64	Compléter : ____ permet d'afficher les variables d'environnement.	shell	fill_blank	30	15	La commande env affiche les variables.	easy	2026-07-27 20:19:02.791354
65	Compléter : la variable spéciale ____ contient le PID du shell.	shell	fill_blank	40	20	$$ représente le PID.	medium	2026-07-27 20:19:02.791354
66	Compléter : ____ permet de lire une entrée utilisateur.	shell	fill_blank	30	15	read lit une entrée.	easy	2026-07-27 20:19:02.791354
67	Compléter : ____ affiche la valeur de la dernière commande.	shell	fill_blank	40	20	$? contient le code de retour.	medium	2026-07-27 20:19:02.791354
68	Compléter : ____ termine immédiatement le script.	shell	fill_blank	30	15	exit termine le script.	easy	2026-07-27 20:19:02.791354
69	Associer chaque opérateur de redirection à son rôle.	shell	combination	60	30	Connaître >, >>, < et 2>.	hard	2026-07-27 20:19:02.791354
70	Associer chaque permission Linux à sa valeur numérique.	shell	combination	60	30	r=4, w=2, x=1.	medium	2026-07-27 20:19:02.791354
71	Associer chaque variable spéciale Bash à sa signification.	shell	combination	60	30	$$, $?, $#, $@.	hard	2026-07-27 20:19:02.791354
72	Écrire un script affichant "Hello World".	shell	shell_code	120	50	Le script doit être exécutable.	easy	2026-07-27 20:19:02.791354
73	Écrire un script parcourant tous les fichiers d'un dossier.	shell	shell_code	180	70	Utiliser une boucle for.	medium	2026-07-27 20:19:02.791354
74	Écrire un script sauvegardant un dossier dans une archive compressée.	shell	shell_code	240	100	Utiliser tar avec gzip.	hard	2026-07-27 20:19:02.791354
\.


--
-- Data for Name: question_choice; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.question_choice (choice_id, question_id, label, content, is_correct, order_index) FROM stdin;
1	1	A	Linus Torvalds	t	1
2	1	B	Richard Stallman	f	2
3	1	C	Dennis Ritchie	f	3
4	1	D	Ken Thompson	f	4
5	2	A	1989	f	1
6	2	B	1991	t	2
7	2	C	1995	f	3
8	2	D	2001	f	4
9	3	A	General Network Utility	f	1
10	3	B	GNU's Not Unix	t	2
11	3	C	Global Network Unit	f	3
12	3	D	Graphical Native Utility	f	4
13	4	A	MIT	f	1
14	4	B	Apache 2.0	f	2
15	4	C	GPL v2	t	3
16	4	D	BSD	f	4
17	5	A	Tux le pingouin	t	1
18	5	B	Beastie le démon	f	2
19	5	C	Konqi le dragon	f	3
20	5	D	GNU le buffle	f	4
21	6	A	CP/M	f	1
22	6	B	Multics	t	2
23	6	C	MS-DOS	f	3
24	6	D	VMS	f	4
25	7	A	Microsoft	f	1
26	7	B	IBM	f	2
27	7	C	Apple	t	3
28	7	D	Google	f	4
29	8	A	Mark Shuttleworth	f	1
30	8	B	Ian Murdock	t	2
31	8	C	Patrick Volkerding	f	3
32	8	D	Matthias Ettrich	f	4
33	9	A	Red Hat	t	1
34	9	B	Ubuntu	f	2
35	9	C	Fedora	f	3
36	9	D	SUSE	f	4
37	10	A	Free and Open Source Software	t	1
38	10	B	Fully Open System Software	f	2
39	10	C	Foundation of Software Standards	f	3
40	10	D	Free Operating System Suite	f	4
41	11	A	pwd	t	1
42	11	B	ls	f	2
43	11	C	cd	f	3
44	11	D	dir	f	4
45	12	A	cat	f	1
46	12	B	ls	t	2
47	12	C	find	f	3
48	12	D	tree	f	4
49	13	A	cd	t	1
50	13	B	mv	f	2
51	13	C	go	f	3
52	13	D	dir	f	4
53	14	A	cat	t	1
54	14	B	make	f	2
55	14	C	run	f	3
56	14	D	open	f	4
57	15	A	mv	f	1
58	15	B	cp	t	2
59	15	C	copy	f	3
60	15	D	dup	f	4
61	16	A	mv	t	1
62	16	B	cp	f	2
63	16	C	ren	f	3
64	16	D	move	f	4
65	17	A	del	f	1
66	17	B	erase	f	2
67	17	C	rm	t	3
68	17	D	delete	f	4
69	18	A	newdir	f	1
70	18	B	mkdir	t	2
71	18	C	touch	f	3
72	18	D	makedir	f	4
73	19	A	top	f	1
74	19	B	ps	t	2
75	19	C	jobs	f	3
76	19	D	proc	f	4
77	20	A	chown	f	1
78	20	B	chmod	t	2
79	20	C	chgrp	f	3
80	20	D	perm	f	4
81	21	reponse	date	t	1
82	22	reponse	df	t	1
83	23	reponse	free	t	1
84	24	reponse	grep	t	1
85	25	reponse	head	t	1
86	26	reponse	tail	t	1
87	27	reponse	chown	t	1
88	28	reponse	whoami	t	1
89	29	reponse	tar -czf backup.tar.gz /data	t	1
90	30	reponse	man ls	t	1
91	31	reponse	ls | sort	t	1
92	32	reponse	ls | wc -l	t	1
93	33	reponse	ps aux | grep ssh	t	1
94	34	reponse	du -ah . | sort -rh | head -5	t	1
95	35	reponse	grep ERROR access.log | wc -l	t	1
96	36	reponse	ls	t	1
97	37	reponse	-r	t	1
98	38	reponse	+x	t	1
99	39	reponse	-mtime	t	1
100	40	reponse	>	t	1
101	41	reponse	for i in {1..10}; do echo $i; done	t	1
102	42	reponse	read -p "Quel est votre nom ? " nom; echo "Bienvenue, $nom !"	t	1
103	43	reponse	if [ -f config.txt ]; then echo "Trouve"; else echo "Absent"; fi	t	1
104	34	A	Linus Torvalds	t	1
105	34	B	Dennis Ritchie	f	2
106	34	C	Richard Stallman	f	3
107	34	D	Ken Thompson	f	4
108	35	A	Ubuntu	f	1
109	35	B	Fedora	f	2
110	35	C	Linux Mint	f	3
111	35	D	Debian	t	4
112	36	A	pwd	t	1
113	36	B	ls	f	2
114	36	C	cd	f	3
115	36	D	whoami	f	4
116	37	A	ls -la	t	1
117	37	B	ls -lh	f	2
118	37	C	find -la	f	3
119	37	D	dir -a	f	4
120	38	A	touch fichier.txt	t	1
121	38	B	mkdir fichier.txt	f	2
122	38	C	cat fichier.txt	f	3
123	38	D	rm fichier.txt	f	4
124	39	A	mkdir projet	t	1
125	39	B	touch projet	f	2
126	39	C	mkfile projet	f	3
127	39	D	cd projet	f	4
128	40	A	cd /home	t	1
129	40	B	pwd /home	f	2
130	40	C	ls /home	f	3
131	40	D	mv /home	f	4
132	41	A	rm fichier.txt	t	1
133	41	B	del fichier.txt	f	2
134	41	C	erase fichier.txt	f	3
135	41	D	drop fichier.txt	f	4
136	42	A	cp source destination	t	1
137	42	B	mv source destination	f	2
138	42	C	ln source destination	f	3
139	42	D	cat source destination	f	4
140	43	A	mv ancien nouveau	t	1
141	43	B	cp ancien nouveau	f	2
142	43	C	rename ancien nouveau	f	3
143	43	D	touch ancien nouveau	f	4
144	44	A	chmod 755 fichier	t	1
145	44	B	chown 755 fichier	f	2
146	44	C	chgrp 755 fichier	f	3
147	44	D	umask 755 fichier	f	4
148	45	A	grep texte fichier.txt	t	1
149	45	B	find texte fichier.txt	f	2
150	45	C	cat texte fichier.txt	f	3
151	45	D	awk texte fichier.txt	f	4
152	46	A	find . -name "*.txt"	t	1
153	46	B	grep . -name "*.txt"	f	2
154	46	C	ls . -name "*.txt"	f	3
155	46	D	cat . -name "*.txt"	f	4
156	47	A	cat fichier.txt	t	1
157	47	B	cd fichier.txt	f	2
158	47	C	chmod fichier.txt	f	3
159	47	D	mkdir fichier.txt	f	4
160	48	A	echo "Bonjour"	t	1
161	48	B	print "Bonjour"	f	2
162	48	C	say "Bonjour"	f	3
163	48	D	show "Bonjour"	f	4
164	49	A	tar -czf archive.tar.gz dossier	t	1
165	49	B	zip -czf archive.tar.gz dossier	f	2
166	49	C	gzip -r archive.tar.gz dossier	f	3
167	49	D	cp -czf archive.tar.gz dossier	f	4
168	50	A	systemctl status sshd	t	1
169	50	B	service reload sshd	f	2
170	50	C	journalctl status sshd	f	3
171	50	D	ps status sshd	f	4
172	51	A	systemctl restart nginx	t	1
173	51	B	systemctl reload nginx now	f	2
174	51	C	service status nginx	f	3
175	51	D	nginx restart systemctl	f	4
176	52	A	sudo apt update	t	1
177	52	B	sudo apt install	f	2
178	52	C	sudo apt upgrade-list	f	3
179	52	D	sudo dpkg update	f	4
180	53	A	sudo dnf install vim	t	1
181	53	B	sudo apt install vim	f	2
182	53	C	sudo yum search vim	f	3
183	53	D	sudo rpm update vim	f	4
184	54	A	chmod +x script.sh	t	1
185	54	B	chown +x script.sh	f	2
186	54	C	chmod run script.sh	f	3
187	54	D	exec +x script.sh	f	4
188	55	A	#!/bin/bash	t	1
189	55	B	#/bin/bash	f	2
190	55	C	#!/usr/bash/env	f	3
191	55	D	bash!/bin	f	4
192	56	A	for i in {1..5}; do echo $i; done	t	1
193	56	B	for i = 1..5 echo $i	f	2
194	56	C	while i in {1..5}; echo $i	f	3
195	56	D	repeat 5 echo $i	f	4
196	57	A	if [ -f fichier ]; then echo OK; fi	t	1
197	57	B	if file fichier then echo OK	f	2
198	57	C	test fichier -f echo OK	f	3
199	57	D	when [ fichier ]; echo OK	f	4
200	58	A	while true; do sleep 1; done	t	1
201	58	B	for true; sleep 1; done	f	2
202	58	C	loop true sleep 1	f	3
203	58	D	while sleep 1 true done	f	4
204	59	A	#!/bin/bash	t	1
205	59	B	#!/bin/sh/bash	f	2
206	59	C	#bash	f	3
207	59	D	/bin/bash#!	f	4
208	60	A	echo "Nom : $USER"	t	1
209	60	B	print "Nom : $USER"	f	2
210	60	C	echo Nom = USER	f	3
211	60	D	whoami "Nom : $USER"	f	4
212	61	A	case "$1" in	t	1
213	61	B	switch "$1" in	f	2
214	61	C	case "$1" then	f	3
215	61	D	select "$1" case	f	4
216	62	A	read nom	t	1
217	62	B	scan nom	f	2
218	62	C	input nom	f	3
219	62	D	get nom	f	4
220	63	A	chmod +x monscript.sh	t	1
221	63	B	chown +x monscript.sh	f	2
222	63	C	run +x monscript.sh	f	3
223	63	D	exec monscript.sh +x	f	4
\.


--
-- Data for Name: two_factor_challenge; Type: TABLE DATA; Schema: public; Owner: pop_quizz_user
--

COPY public.two_factor_challenge (challenge_id, player_id, command, expected_answer, validated, created_at, expires_at) FROM stdin;
1	1	Donnez la commande qui affiche les 5 processus consommant le plus de mémoire, triés par ordre décroissant.	ps aux --sort=-%mem | head -5	f	2026-06-30 15:32:31.341266	2026-06-30 15:42:31.341266
2	2	Donnez la commande qui recherche récursivement, dans /etc, tous les fichiers modifiés au cours des 7 derniers jours.	find /etc -type f -mtime -7	f	2026-06-30 15:32:31.341266	2026-06-30 15:42:31.341266
3	3	Donnez la commande qui affiche le nombre total de connexions TCP actuellement à l'état ESTABLISHED.	netstat -ant | grep ESTABLISHED | wc -l	f	2026-06-30 15:32:31.341266	2026-06-30 15:42:31.341266
\.


--
-- Name: admin_admin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.admin_admin_id_seq', 7, true);


--
-- Name: answer_answer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.answer_answer_id_seq', 7, true);


--
-- Name: contest_contest_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.contest_contest_id_seq', 28, true);


--
-- Name: contest_player_contest_player_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.contest_player_contest_player_id_seq', 25, true);


--
-- Name: contest_question_contest_question_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.contest_question_contest_question_id_seq', 533, true);


--
-- Name: contest_session_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.contest_session_session_id_seq', 1, false);


--
-- Name: game_event_log_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.game_event_log_event_id_seq', 7, true);


--
-- Name: player_player_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.player_player_id_seq', 22, true);


--
-- Name: question_choice_choice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.question_choice_choice_id_seq', 223, true);


--
-- Name: question_question_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.question_question_id_seq', 74, true);


--
-- Name: two_factor_challenge_challenge_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pop_quizz_user
--

SELECT pg_catalog.setval('public.two_factor_challenge_challenge_id_seq', 3, true);


--
-- Name: admin admin_email_key; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.admin
    ADD CONSTRAINT admin_email_key UNIQUE (email);


--
-- Name: admin admin_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.admin
    ADD CONSTRAINT admin_pkey PRIMARY KEY (admin_id);


--
-- Name: answer answer_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.answer
    ADD CONSTRAINT answer_pkey PRIMARY KEY (answer_id);


--
-- Name: answer answer_unique; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.answer
    ADD CONSTRAINT answer_unique UNIQUE (contest_question_id, player_id);


--
-- Name: contest contest_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest
    ADD CONSTRAINT contest_pkey PRIMARY KEY (contest_id);


--
-- Name: contest_player contest_player_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_player
    ADD CONSTRAINT contest_player_pkey PRIMARY KEY (contest_player_id);


--
-- Name: contest_player contest_player_unique; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_player
    ADD CONSTRAINT contest_player_unique UNIQUE (contest_id, player_id);


--
-- Name: contest_question contest_question_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_question
    ADD CONSTRAINT contest_question_pkey PRIMARY KEY (contest_question_id);


--
-- Name: contest_session contest_session_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_session
    ADD CONSTRAINT contest_session_pkey PRIMARY KEY (session_id);


--
-- Name: player player_email_key; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.player
    ADD CONSTRAINT player_email_key UNIQUE (email);


--
-- Name: player player_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.player
    ADD CONSTRAINT player_pkey PRIMARY KEY (player_id);


--
-- Name: player player_username_key; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.player
    ADD CONSTRAINT player_username_key UNIQUE (username);


--
-- Name: question_choice question_choice_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.question_choice
    ADD CONSTRAINT question_choice_pkey PRIMARY KEY (choice_id);


--
-- Name: question question_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.question
    ADD CONSTRAINT question_pkey PRIMARY KEY (question_id);


--
-- Name: two_factor_challenge two_factor_challenge_pkey; Type: CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.two_factor_challenge
    ADD CONSTRAINT two_factor_challenge_pkey PRIMARY KEY (challenge_id);


--
-- Name: idx_answer_contest_question; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_answer_contest_question ON public.answer USING btree (contest_question_id);


--
-- Name: idx_answer_contest_question_player; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_answer_contest_question_player ON public.answer USING btree (contest_question_id, player_id);


--
-- Name: idx_answer_player; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_answer_player ON public.answer USING btree (player_id);


--
-- Name: idx_answer_submitted; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_answer_submitted ON public.answer USING btree (submitted_at);


--
-- Name: idx_contest_player_contest; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_player_contest ON public.contest_player USING btree (contest_id);


--
-- Name: idx_contest_player_player; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_player_player ON public.contest_player USING btree (player_id);


--
-- Name: idx_contest_question_contest; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_question_contest ON public.contest_question USING btree (contest_id);


--
-- Name: idx_contest_question_order; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_question_order ON public.contest_question USING btree (order_index);


--
-- Name: idx_contest_question_status; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_question_status ON public.contest_question USING btree (status);


--
-- Name: idx_contest_session_contest; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_session_contest ON public.contest_session USING btree (contest_id);


--
-- Name: idx_contest_status; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_contest_status ON public.contest USING btree (status);


--
-- Name: idx_game_event_log_contest; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_game_event_log_contest ON public.game_event_log USING btree (contest_id);


--
-- Name: idx_game_event_log_created; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_game_event_log_created ON public.game_event_log USING btree (created_at);


--
-- Name: idx_question_category; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_question_category ON public.question USING btree (category);


--
-- Name: idx_question_choice_question; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_question_choice_question ON public.question_choice USING btree (question_id);


--
-- Name: idx_question_type; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_question_type ON public.question USING btree (type);


--
-- Name: idx_two_factor_challenge_expires; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_two_factor_challenge_expires ON public.two_factor_challenge USING btree (expires_at);


--
-- Name: idx_two_factor_challenge_player; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE INDEX idx_two_factor_challenge_player ON public.two_factor_challenge USING btree (player_id);


--
-- Name: unique_first_blood_per_question; Type: INDEX; Schema: public; Owner: pop_quizz_user
--

CREATE UNIQUE INDEX unique_first_blood_per_question ON public.answer USING btree (contest_question_id) WHERE (first_blood = true);


--
-- Name: answer trigger_log_answer_event; Type: TRIGGER; Schema: public; Owner: pop_quizz_user
--

CREATE TRIGGER trigger_log_answer_event AFTER INSERT ON public.answer FOR EACH ROW EXECUTE FUNCTION public.log_answer_event();


--
-- Name: answer trigger_validate_question_open; Type: TRIGGER; Schema: public; Owner: pop_quizz_user
--

CREATE TRIGGER trigger_validate_question_open BEFORE INSERT ON public.answer FOR EACH ROW EXECUTE FUNCTION public.validate_question_open();


--
-- Name: answer trigger_validate_timeout; Type: TRIGGER; Schema: public; Owner: pop_quizz_user
--

CREATE TRIGGER trigger_validate_timeout BEFORE INSERT ON public.answer FOR EACH ROW EXECUTE FUNCTION public.validate_timeout();


--
-- Name: answer fk_answer_contest_question; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.answer
    ADD CONSTRAINT fk_answer_contest_question FOREIGN KEY (contest_question_id) REFERENCES public.contest_question(contest_question_id) ON DELETE CASCADE;


--
-- Name: answer fk_answer_player; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.answer
    ADD CONSTRAINT fk_answer_player FOREIGN KEY (player_id) REFERENCES public.player(player_id) ON DELETE CASCADE;


--
-- Name: contest fk_contest_admin; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest
    ADD CONSTRAINT fk_contest_admin FOREIGN KEY (created_by) REFERENCES public.admin(admin_id);


--
-- Name: contest_player fk_contest_player_contest; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_player
    ADD CONSTRAINT fk_contest_player_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id) ON DELETE CASCADE;


--
-- Name: contest_player fk_contest_player_player; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_player
    ADD CONSTRAINT fk_contest_player_player FOREIGN KEY (player_id) REFERENCES public.player(player_id) ON DELETE CASCADE;


--
-- Name: contest_question fk_contest_question_contest; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_question
    ADD CONSTRAINT fk_contest_question_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id) ON DELETE CASCADE;


--
-- Name: contest_question fk_contest_question_question; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_question
    ADD CONSTRAINT fk_contest_question_question FOREIGN KEY (question_id) REFERENCES public.question(question_id);


--
-- Name: contest_session fk_contest_session_contest; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_session
    ADD CONSTRAINT fk_contest_session_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id);


--
-- Name: contest_session fk_contest_session_player; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.contest_session
    ADD CONSTRAINT fk_contest_session_player FOREIGN KEY (player_id) REFERENCES public.player(player_id);


--
-- Name: game_event_log fk_game_event_log_contest; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.game_event_log
    ADD CONSTRAINT fk_game_event_log_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id) ON DELETE CASCADE;


--
-- Name: question_choice fk_question_choice_question; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.question_choice
    ADD CONSTRAINT fk_question_choice_question FOREIGN KEY (question_id) REFERENCES public.question(question_id) ON DELETE CASCADE;


--
-- Name: two_factor_challenge fk_two_factor_challenge_player; Type: FK CONSTRAINT; Schema: public; Owner: pop_quizz_user
--

ALTER TABLE ONLY public.two_factor_challenge
    ADD CONSTRAINT fk_two_factor_challenge_player FOREIGN KEY (player_id) REFERENCES public.player(player_id);


--
-- PostgreSQL database dump complete
--

\unrestrict dP4dIcyu4PvJGbA19Drf1qWV6GXMqMefsQK9z0oZM8CbpMaagqjPSKwW6CqqRBu

